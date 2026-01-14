#!/bin/bash
# Title: Flock Safety Device Detector Scanner
# Author: marcdel
# Description: Scanner that monitors for Flock Safety surveillance devices
# Version: 2.0
#
# Can be sourced for foreground mode or run standalone for background mode.

# ============================================================================
# CONFIGURATION
# ============================================================================

# Determine script directory (works when sourced or run directly)
if [[ -n "$SCANNER_SCRIPT_DIR" ]]; then
    _SCANNER_DIR="$SCANNER_SCRIPT_DIR"
elif [[ -n "${BASH_SOURCE[0]}" ]]; then
    _SCANNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    _SCANNER_DIR="$(pwd)"
fi

PID_FILE="/tmp/flock_detector.pid"
LOG_FILE="/tmp/flock_detector.log"
SIGNATURES_FILE="$_SCANNER_DIR/flock_signatures.sh"
CONFIG_FILE="$_SCANNER_DIR/config.sh"
SEEN_DEVICES_FILE="/tmp/flock_seen_devices.txt"
DETECTIONS_FILE=""  # Set on init with timestamp

# Default config values (can be overridden by config.sh)
WIFI_SCAN_DURATION=10
BT_SCAN_DURATION=10
SCAN_INTERVAL=5
ALERT_COOLDOWN=300
LOOT_DIR="/root/loot/flock_detector"

# Load user config if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Track if scanner is initialized
_SCANNER_INITIALIZED=0

# ============================================================================
# INITIALIZATION
# ============================================================================

init_scanner() {
    if [[ $_SCANNER_INITIALIZED -eq 1 ]]; then
        return 0
    fi

    if [[ ! -f "$SIGNATURES_FILE" ]]; then
        log_error "Signatures file not found: $SIGNATURES_FILE"
        return 1
    fi
    source "$SIGNATURES_FILE"

    touch "$SEEN_DEVICES_FILE"

    # Create loot directory and set timestamped filename
    mkdir -p "$LOOT_DIR"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    DETECTIONS_FILE="$LOOT_DIR/detections_${timestamp}.json"

    # Initialize JSON file with empty array
    echo '[]' > "$DETECTIONS_FILE"

    _SCANNER_INITIALIZED=1

    log_info "Scanner initialized"
    log_info "Signatures loaded: ${#FLOCK_MAC_PREFIXES[@]} MAC prefixes, ${#FLOCK_SSID_PATTERNS[@]} SSID patterns, ${#FLOCK_BLE_NAMES[@]} BLE names"
    log_info "Detections will be saved to: $DETECTIONS_FILE"

    return 0
}

# ============================================================================
# LOGGING
# ============================================================================

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local formatted="[$timestamp] [$level] $message"

    if [[ "$SCANNER_FOREGROUND" == "1" ]]; then
        # Foreground mode: output to screen
        case "$level" in
            DETECTION) LOG red "$formatted" ;;
            ERROR)     LOG red "$formatted" ;;
            *)         LOG "$formatted" ;;
        esac
    else
        # Background mode: output to log file
        echo "$formatted" >> "$LOG_FILE"
    fi
}

log_info() {
    log_message "INFO" "$1"
}

log_debug() {
    if [[ "$DEBUG_MODE" == "0" ]]; then
        return
    fi

    log_message "INFO" "$1"
}

log_detection() {
    log_message "DETECTION" "$1"
}

log_error() {
    log_message "ERROR" "$1"
}

record_detection() {
    local mac="$1"
    local name="$2"
    local type="$3"
    local method="$4"
    local detail="$5"
    local rssi="$6"
    local timestamp=$(date -Iseconds)

    # Create new detection object
    local detection=$(jq -n \
        --arg ts "$timestamp" \
        --arg mac "$mac" \
        --arg name "$name" \
        --arg type "$type" \
        --arg method "$method" \
        --arg detail "$detail" \
        --arg rssi "$rssi" \
        '{
            timestamp: $ts,
            mac: $mac,
            name: $name,
            type: $type,
            detection_method: $method,
            detection_detail: $detail,
            rssi: $rssi
        }')

    # Append to JSON array
    local tmp_file="${DETECTIONS_FILE}.tmp"
    jq --argjson new "$detection" '. += [$new]' "$DETECTIONS_FILE" > "$tmp_file" && \
        mv "$tmp_file" "$DETECTIONS_FILE"
}

# ============================================================================
# ALERTS
# ============================================================================

# Check if we should alert for this device (deduplication)
should_alert() {
    local mac="$1"
    local current_time=$(date +%s)
    
    # Check if device was seen recently
    if grep -q "^$mac:" "$SEEN_DEVICES_FILE" 2>/dev/null; then
        local last_seen=$(grep "^$mac:" "$SEEN_DEVICES_FILE" | cut -d: -f2)
        local elapsed=$((current_time - last_seen))
        
        if [[ $elapsed -lt $ALERT_COOLDOWN ]]; then
            return 1  # Don't alert, seen too recently
        fi
    fi
    
    # Update seen time
    grep -v "^$mac:" "$SEEN_DEVICES_FILE" > "${SEEN_DEVICES_FILE}.tmp" 2>/dev/null || true
    echo "$mac:$current_time" >> "${SEEN_DEVICES_FILE}.tmp"
    mv "${SEEN_DEVICES_FILE}.tmp" "$SEEN_DEVICES_FILE"
    
    return 0  # Should alert
}

# Send alert for detected Flock device
send_alert() {
    local mac="$1"
    local name="$2"
    local type="$3"
    local method="$4"
    local detail="$5"
    local rssi="$6"
    
    if ! should_alert "$mac"; then
        log_info "Skipping alert for $mac (already seen recently)"
        return
    fi
    
    log_detection "FLOCK DEVICE: MAC=$mac NAME=$name TYPE=$type METHOD=$method DETAIL=$detail RSSI=$rssi"
    record_detection "$mac" "$name" "$type" "$method" "$detail" "$rssi"
    
    # Visual alert - red LED
    LED R 255 G 0 B 0 2>/dev/null || true
    
    # Vibration
    VIBRATE 500 2>/dev/null || true
    
    # Screen alert
    local alert_msg="FLOCK DEVICE DETECTED!

MAC: $mac
Type: $type
Name: $name
Method: $method
Signal: ${rssi}dBm"
    
    ALERT "$alert_msg" 2>/dev/null || true
    
    # Keep LED on briefly then turn off
    sleep 2
    LED OFF 2>/dev/null || true
}

# ============================================================================
# WIFI SCANNING
# ============================================================================

scan_wifi() {
    log_info "Starting WiFi scan..."
    
    # Get APs from pineap
    local json=$(_pineap RECON APS format=json limit=50 2>/dev/null)
    
    if [[ -z "$json" ]] || [[ "$json" == "[]" ]]; then
        log_info "No WiFi data from RECON APS"
        return
    fi
    
    # Parse APs
    local count=$(echo "$json" | jq 'length')
    for ((i=0; i<count; i++)); do
        local mac=$(echo "$json" | jq -r ".[$i].mac")
        local ssid=$(echo "$json" | jq -r ".[$i].ssid // \"[Hidden]\"")
        local rssi=$(echo "$json" | jq -r ".[$i].signal // -100")
        
        if flock_check_device "$mac" "$ssid" "wifi"; then
            send_alert "$mac" "$ssid" "WiFi AP" "$FLOCK_DETECTION_METHOD" "$FLOCK_DETECTION_DETAIL" "$rssi"
        else
            log_debug "No match found for WiFi device: $mac $ssid"
        fi
    done
    
    # Also use IRSEARCH for SSID pattern matching
    local search_result=$(_pineap RECON IRSEARCH "$FLOCK_SSID_REGEX" format=json limit=20 2>/dev/null)
    
    if [[ -n "$search_result" ]] && [[ "$search_result" != "[]" ]]; then
        local search_count=$(echo "$search_result" | jq 'length')
        for ((i=0; i<search_count; i++)); do
            local mac=$(echo "$search_result" | jq -r ".[$i].mac")
            local ssid=$(echo "$search_result" | jq -r ".[$i].ssid // \"\"")
            local rssi=$(echo "$search_result" | jq -r ".[$i].signal // -100")
            
            # Validate IRSEARCH results
            if flock_check_device "$mac" "$ssid" "wifi"; then
                send_alert "$mac" "$ssid" "WiFi AP" "$FLOCK_DETECTION_METHOD" "$FLOCK_DETECTION_DETAIL" "$rssi"
            else
                log_debug "Found WiFi device: $mac $ssid with IRSEARCH but it did not match any signatures."
            fi
        done
    fi
    
    log_info "WiFi scan complete. Checked $count WiFi devices and $search_count IRSEARCH results."
}

# ============================================================================
# BLUETOOTH SCANNING
# ============================================================================

scan_bluetooth() {
    log_info "Starting Bluetooth scan..."
    
    # Make sure Bluetooth is available
    if ! command -v hcitool &>/dev/null; then
        log_error "hcitool not available"
        return
    fi
    
    # BLE scan
    local ble_cache="/tmp/flock_ble_scan.txt"
    rm -f "$ble_cache"
    
    # Start BLE scan in background
    hcitool lescan --duplicates 2>/dev/null > "$ble_cache" &
    local scan_pid=$!
    
    # Let it scan for configured duration
    sleep "$BT_SCAN_DURATION"
    
    # Stop the scan
    kill $scan_pid 2>/dev/null
    wait $scan_pid 2>/dev/null
    
    # Process BLE results
    if [[ -s "$ble_cache" ]]; then
        while read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" == *"LE Scan"* ]] && continue
            
            local mac=$(echo "$line" | awk '{print $1}')
            local name=$(echo "$line" | cut -d' ' -f2-)
            
            [[ -z "$mac" ]] && continue
            
            if flock_check_device "$mac" "$name" "ble"; then
                send_alert "$mac" "$name" "BLE Device" "$FLOCK_DETECTION_METHOD" "$FLOCK_DETECTION_DETAIL" "N/A"
            else
                log_debug "No match found for BLE device: $mac $name"
            fi
        done < "$ble_cache"
    fi
    
    rm -f "$ble_cache"
    
    # Classic Bluetooth inquiry
    log_info "Classic Bluetooth inquiry..."
    local classic_result=$(timeout 5 hcitool inq 2>/dev/null)
    
    if [[ -n "$classic_result" ]]; then
        while read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" == *"Inquiring"* ]] && continue
            
            local mac=$(echo "$line" | awk '{print $1}')
            [[ -z "$mac" ]] && continue
            
            local name=$(hcitool name "$mac" 2>/dev/null || echo "Unknown")
            
            if flock_check_device "$mac" "$name" "ble"; then
                send_alert "$mac" "$name" "Classic BT" "$FLOCK_DETECTION_METHOD" "$FLOCK_DETECTION_DETAIL" "N/A"
            else
                log_debug "No match found for Classic BT device: $mac $name"
            fi
        done <<< "$classic_result"
    fi
    
    log_info "Bluetooth scan complete"
}

# ============================================================================
# SCAN FUNCTIONS
# ============================================================================

# Run a single scan cycle (WiFi + Bluetooth in parallel)
run_single_scan() {
    scan_wifi &
    local wifi_pid=$!
    
    scan_bluetooth &
    local bt_pid=$!
    
    # Wait for both to complete
    wait $wifi_pid 2>/dev/null
    wait $bt_pid 2>/dev/null
}

# Run continuous scan loop (for background mode)
run_scan_loop() {
    log_info "Starting continuous scan loop..."
    
    while true; do
        run_single_scan
        sleep "$SCAN_INTERVAL"
    done
}

# ============================================================================
# CLEANUP
# ============================================================================

scanner_cleanup() {
    log_info "Scanner stopping..."
    
    # Kill any running scans
    killall hcitool 2>/dev/null || true
    
    # Turn off LED
    LED OFF 2>/dev/null || true
    
    # Remove PID file
    rm -f "$PID_FILE"
    rm -f "$SEEN_DEVICES_FILE"
    rm -f /tmp/flock_ble_scan.txt
    
    log_info "Scanner stopped"
}

# ============================================================================
# STANDALONE MODE (Background)
# ============================================================================

# Only run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Set up signal handlers
    trap scanner_cleanup EXIT INT TERM
    
    # Initialize
    if ! init_scanner; then
        echo "Failed to initialize scanner" >&2
        exit 1
    fi
    
    log_info "Flock Detector starting in background mode..."
    
    # Write PID file
    echo $$ > "$PID_FILE"
    
    # Run the scan loop
    run_scan_loop
fi
