#!/bin/bash
# Flock Safety Device Signatures Database
# Source: https://github.com/colonelpanichacks/flock-you
#         https://github.com/jbohack/nyanBOX
# Version: 1.0

# ============================================================================
# KNOWN MAC ADDRESS PREFIXES (OUI)
# ============================================================================

# FS Ext Battery devices
FLOCK_MAC_PREFIXES_FS_EXT=(
    "58:8e:81"
    "cc:cc:cc"
    "ec:1b:bd"
    "90:35:ea"
    "04:0d:84"
    "f0:82:c0"
    "1c:34:f1"
    "38:5b:44"
    "94:34:69"
    "b4:e3:f9"
)

# Flock WiFi devices
FLOCK_MAC_PREFIXES_WIFI=(
    "70:c9:4e"
    "3c:91:80"
    "d8:f3:bc"
    "80:30:49"
    "14:5a:fc"
    "74:4c:a1"
    "08:3a:88"
    "9c:2f:9d"
    "94:08:53"
    "e4:aa:ea"
)

# Combined list of all MAC prefixes
FLOCK_MAC_PREFIXES=(
    "${FLOCK_MAC_PREFIXES_FS_EXT[@]}"
    "${FLOCK_MAC_PREFIXES_WIFI[@]}"
)

# ============================================================================
# WIFI SSID PATTERNS
# ============================================================================

FLOCK_SSID_PATTERNS=(
    "flock"
    "Flock"
    "FLOCK"
    "FS Ext Battery"
    "Penguin"
    "Pigvision"
)

# Regex pattern for SSID matching (case insensitive)
FLOCK_SSID_REGEX="flock|FS Ext Battery|Penguin|Pigvision"

# ============================================================================
# BLE DEVICE NAME PATTERNS
# ============================================================================

FLOCK_BLE_NAMES=(
    "FS Ext Battery"
    "Penguin"
    "Flock"
    "Pigvision"
)

# ============================================================================
# DETECTION FUNCTIONS
# ============================================================================

# Check if a MAC address matches known Flock prefixes
# Usage: flock_check_mac_prefix "aa:bb:cc:dd:ee:ff"
# Returns: 0 if match, 1 if no match
# Sets: FLOCK_MATCH_TYPE with the device type if matched
flock_check_mac_prefix() {
    local mac="$1"
    local mac_prefix="${mac:0:8}"  # First 8 chars (aa:bb:cc)
    local mac_lower=$(echo "$mac_prefix" | tr '[:upper:]' '[:lower:]')
    
    # Check FS Ext Battery prefixes
    for prefix in "${FLOCK_MAC_PREFIXES_FS_EXT[@]}"; do
        local prefix_lower=$(echo "$prefix" | tr '[:upper:]' '[:lower:]')
        if [[ "$mac_lower" == "$prefix_lower" ]]; then
            FLOCK_MATCH_TYPE="FS Ext Battery"
            return 0
        fi
    done
    
    # Check Flock WiFi prefixes
    for prefix in "${FLOCK_MAC_PREFIXES_WIFI[@]}"; do
        local prefix_lower=$(echo "$prefix" | tr '[:upper:]' '[:lower:]')
        if [[ "$mac_lower" == "$prefix_lower" ]]; then
            FLOCK_MATCH_TYPE="Flock WiFi"
            return 0
        fi
    done
    
    FLOCK_MATCH_TYPE=""
    return 1
}

# Check if an SSID matches known Flock patterns
# Usage: flock_check_ssid_pattern "NetworkName"
# Returns: 0 if match, 1 if no match
# Sets: FLOCK_MATCH_PATTERN with the matched pattern
flock_check_ssid_pattern() {
    local ssid="$1"
    local ssid_lower=$(echo "$ssid" | tr '[:upper:]' '[:lower:]')
    
    for pattern in "${FLOCK_SSID_PATTERNS[@]}"; do
        local pattern_lower=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
        if [[ "$ssid_lower" == *"$pattern_lower"* ]]; then
            FLOCK_MATCH_PATTERN="$pattern"
            return 0
        fi
    done
    
    FLOCK_MATCH_PATTERN=""
    return 1
}

# Check if a BLE device name matches known Flock patterns
# Usage: flock_check_ble_name "DeviceName"
# Returns: 0 if match, 1 if no match
# Sets: FLOCK_MATCH_PATTERN with the matched pattern
flock_check_ble_name() {
    local name="$1"
    local name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    
    for pattern in "${FLOCK_BLE_NAMES[@]}"; do
        local pattern_lower=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')
        if [[ "$name_lower" == *"$pattern_lower"* ]]; then
            FLOCK_MATCH_PATTERN="$pattern"
            return 0
        fi
    done
    
    FLOCK_MATCH_PATTERN=""
    return 1
}

# Check a device against all detection methods
# Usage: flock_check_device "mac" "ssid_or_name" "type"
# type: "wifi" or "ble"
# Returns: 0 if match, 1 if no match
# Sets: FLOCK_DETECTION_METHOD and FLOCK_DETECTION_DETAIL
flock_check_device() {
    local mac="$1"
    local name="$2"
    local type="$3"
    
    FLOCK_DETECTION_METHOD=""
    FLOCK_DETECTION_DETAIL=""
    
    # Check MAC prefix first
    if flock_check_mac_prefix "$mac"; then
        FLOCK_DETECTION_METHOD="MAC Prefix"
        FLOCK_DETECTION_DETAIL="$FLOCK_MATCH_TYPE"
        return 0
    fi
    
    # Check name/SSID based on type
    if [[ "$type" == "wifi" ]]; then
        if flock_check_ssid_pattern "$name"; then
            FLOCK_DETECTION_METHOD="SSID Pattern"
            FLOCK_DETECTION_DETAIL="$FLOCK_MATCH_PATTERN"
            return 0
        fi
    elif [[ "$type" == "ble" ]]; then
        if flock_check_ble_name "$name"; then
            FLOCK_DETECTION_METHOD="BLE Name"
            FLOCK_DETECTION_DETAIL="$FLOCK_MATCH_PATTERN"
            return 0
        fi
    fi
    
    return 1
}
