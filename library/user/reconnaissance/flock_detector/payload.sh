#!/bin/bash
# Title: Flock Detector
# Category: Reconnaissance
# Description: Flock "Safety" device detector
# Author: marcdel
# Version: 1.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Runtime files
PID_FILE="/tmp/flock_detector.pid"
LOG_FILE="/tmp/flock_detector.log"

MENU_TEXT="Choose your adventure:
1) Run in foreground
2) Run in background
3) Stop background
4) View status
5) View logs
0) Exit"

show_menu() {
    PROMPT "$MENU_TEXT"
    local choice=$(NUMBER_PICKER "Select option" "1")
    case $? in
        $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED|$DUCKYSCRIPT_ERROR)
            echo "0"
            return
            ;;
    esac
    echo "$choice"
}

silly_banner() {
    LOG "================================"
    LOG "   ______        __  "
    LOG "  / __/ /__ ____/ /__"
    LOG " / _// / _ Y __/  '_/"
    LOG "/_/ /_/\\___|__/_/\\_\\ "
    LOG "                     "
    LOG ""
}

is_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        # Stale PID file
        rm -f "$PID_FILE"
    fi
    return 1
}

stop_scanner() {
    if [ ! -f "$PID_FILE" ]; then
        return 0
    fi

    local pid=$(cat "$PID_FILE")
    
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$PID_FILE"
        return 0
    fi

    # Send TERM signal
    kill "$pid" 2>/dev/null
    sleep 1

    # Force kill if still running
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null
        sleep 0.5
    fi

    # Cleanup
    killall hcitool 2>/dev/null || true
    rm -f "$PID_FILE"
    rm -f /tmp/flock_ble_scan.txt
    rm -f /tmp/flock_seen_devices.txt
    
    LED OFF 2>/dev/null || true
}

run_foreground() {
    if is_running; then
        LOG yellow "Scanner is already running in background."
        LOG yellow "Stop it first before running in foreground."
        sleep 2
        return 1
    fi

    LOG ""
    LOG green "Starting Flock Detector..."
    LOG "Scanning for Flock Safety devices"
    LOG ""
    LOG "Press B to stop"
    LOG ""

    # Start scanner in background (but attached to this session)
    export SCANNER_SCRIPT_DIR="$SCRIPT_DIR"
    export SCANNER_FOREGROUND=1
    "$SCRIPT_DIR/scanner.sh" &
    local scanner_pid=$!

    # Green LED to indicate running
    LED R 0 G 255 B 0 2>/dev/null || true

    # Wait for user to press B
    while true; do
        local btn=$(WAIT_FOR_INPUT)
        if [[ "$btn" == "B" ]]; then
            break
        fi
    done

    # Stop the scanner
    LOG ""
    LOG yellow "Stopping scanner..."
    
    kill "$scanner_pid" 2>/dev/null
    wait "$scanner_pid" 2>/dev/null
    
    # Cleanup
    killall hcitool 2>/dev/null || true
    rm -f "$PID_FILE"
    rm -f /tmp/flock_ble_scan.txt
    rm -f /tmp/flock_seen_devices.txt
    LED OFF 2>/dev/null || true

    LOG green "Scanner stopped."
    sleep 1
}

run_background() {
    if is_running; then
        local pid=$(cat "$PID_FILE")
        LOG yellow "Scanner is already running (PID: $pid)"
        sleep 2
        return 1
    fi

    LOG ""
    LOG green "Starting Flock Detector in background..."

    # Clear old log entries (keep last 100 lines)
    if [ -f "$LOG_FILE" ]; then
        tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi

    # Start scanner in background
    export SCANNER_SCRIPT_DIR="$SCRIPT_DIR"
    export SCANNER_FOREGROUND=0
    (trap '' HUP; bash "$SCRIPT_DIR/scanner.sh" 2>&1) &
    local scanner_pid=$!

    # Give it a moment to start
    sleep 1

    # Verify it started
    if kill -0 "$scanner_pid" 2>/dev/null; then
        LOG green "Scanner started (PID: $scanner_pid)"
        LED R 0 G 255 B 0 2>/dev/null || true
        sleep 1
        LED OFF 2>/dev/null || true
    else
        LOG red "Failed to start scanner"
        rm -f "$PID_FILE"
    fi

    sleep 1
}

stop_process() {
    if ! is_running; then
        LOG yellow "Scanner is not running"
        sleep 2
        return 0
    fi

    local pid=$(cat "$PID_FILE")
    LOG ""
    LOG yellow "Stopping scanner (PID: $pid)..."
    
    stop_scanner

    LOG green "Scanner stopped"
    sleep 1
}

view_status() {
    LOG ""
    LOG "================================"
    LOG "Flock Detector Status"
    LOG "================================"
    
    if is_running; then
        local pid=$(cat "$PID_FILE")
        LOG green "Status: RUNNING"
        LOG "PID: $pid"
    else
        LOG yellow "Status: STOPPED"
    fi
    
    LOG ""
    
    if [ -f "$LOG_FILE" ]; then
        local line_count=$(wc -l < "$LOG_FILE")
        local detection_count=$(grep -c "DETECTION" "$LOG_FILE" 2>/dev/null || echo 0)
        LOG "Log file: $LOG_FILE"
        LOG "Log lines: $line_count"
        LOG "Detections: $detection_count"
    else
        LOG "No log file yet"
    fi
    
    LOG ""
    LOG "Press any button to continue..."
    WAIT_FOR_INPUT > /dev/null
}

view_logs() {
    LOG ""
    LOG "================================"
    LOG "Flock Detector Logs"
    LOG "================================"
    LOG ""
    LOG "Press B to stop."
    LOG ""
    
    if [ ! -f "$LOG_FILE" ]; then
        LOG "(no log file yet)"
        LOG ""
        LOG "Press any button to continue..."
        WAIT_FOR_INPUT > /dev/null
        return
    fi
    
    # Show last 10 lines first
    tail -10 "$LOG_FILE" | while IFS= read -r line; do
        if [[ "$line" == *"DETECTION"* ]]; then
            LOG red "$line"
        else
            LOG "$line"
        fi
    done
    
    # Start tailing, piping through LOG
    (tail -f "$LOG_FILE" | while IFS= read -r line; do
        if [[ "$line" == *"DETECTION"* ]]; then
            LOG red "$line"
        else
            LOG "$line"
        fi
    done)
}

main() {
    silly_banner
    
    while true; do
        choice=$(show_menu)

        case $choice in
            1) run_foreground ;;
            2) run_background ;;
            3) stop_process ;;
            4) view_status ;;
            5) view_logs ;;
            0) exit 0 ;;
            *)
                LOG ""
                LOG red "Invalid option"
                ;;
        esac
    done
}

main
