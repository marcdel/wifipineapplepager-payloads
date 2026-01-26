#!/bin/bash
#
# Title: Recon DB Explorer
# Description: Web-based viewer for recon.db database
# Author: marcdel
# Version: 1.0.0
#
# Runs uhttpd with CGI to browse recon.db from your browser.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$SCRIPT_DIR/www"
PORT=8889
PID_FILE="/tmp/recon_db_explorer.pid"
INIT_SCRIPT="/etc/init.d/recon_db_explorer"
LOG_FILE="/tmp/recon_db_explorer.log"

log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Check if user confirmed (works with old and new firmware)
user_confirmed() {
    [ "$1" = "true" ] || [ "$1" = "$DUCKYSCRIPT_USER_CONFIRMED" ]
}

get_pager_ip() {
    for iface in br-lan eth0 wlan0 usb0; do
        IP=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d'/' -f1 | head -1)
        [ -n "$IP" ] && echo "$IP" && return
    done
    echo "172.16.52.1"
}

LOG ""
LOG "cyan" '+==============================+'
LOG "cyan" '|  RECON DB EXPLORER v1.0.0  |'
LOG "cyan" '+==============================+'
LOG ""
LOG "yellow" '|  ~ Database Viewer ~    |'
LOG ""

log_debug "Checking if init script exists: $INIT_SCRIPT (exists: $([ -f "$INIT_SCRIPT" ] && echo yes || echo no))"

if [ -f "$INIT_SCRIPT" ] && "$INIT_SCRIPT" running 2>/dev/null; then
    log_debug "Service is already running"
    LOG "green" "Recon Explorer service is running"
    PAGER_IP=$(get_pager_ip)
    LOG "green" "http://$PAGER_IP:$PORT"
    LOG ""
    resp=$(CONFIRMATION_DIALOG "Stop service?")
    if user_confirmed "$resp"; then
        LOG "yellow" "Stopping service..."
        "$INIT_SCRIPT" stop
        "$INIT_SCRIPT" disable
        rm -f "$INIT_SCRIPT"
        LOG "cyan" "Service stopped"
    fi
    exit 0
fi

AUTO_MODE=$(PAYLOAD_GET_CONFIG recon_db_explorer auto_mode 2>/dev/null)
RUN_MODE=$(PAYLOAD_GET_CONFIG recon_db_explorer run_mode 2>/dev/null)

if [ "$AUTO_MODE" = "true" ]; then
    if [ "$RUN_MODE" = "background" ]; then
        resp="true"
        LOG "cyan" "Auto-starting background mode..."
    else
        resp=""
        LOG "cyan" "Auto-starting foreground mode..."
    fi
else
    resp=$(CONFIRMATION_DIALOG "Run as background service?")
fi

if user_confirmed "$resp"; then
    log_debug "Background mode selected"
    LOG "cyan" "Starting as service..."

    if ! command -v uhttpd >/dev/null 2>&1; then
        LOG "yellow" "uhttpd required (~28KB)"
        resp=$(CONFIRMATION_DIALOG "Install uhttpd?")
        if user_confirmed "$resp"; then
            LOG "cyan" "Installing uhttpd..."
            opkg update >/dev/null 2>&1
            if ! opkg install uhttpd; then
                LOG "red" "Install failed!"
                exit 1
            fi
        else
            LOG "red" "Cannot run without uhttpd"
            exit 1
        fi
    fi

    [ ! -f "$WEB_DIR/index.html" ] && { LOG "red" "Files not found!"; log_debug "ERROR: $WEB_DIR/index.html not found"; exit 1; }

    # Update the init script with the actual script directory before copying
    INIT_SRC="$SCRIPT_DIR/recon_explorer.init"
    log_debug "Copying init script from $INIT_SRC to $INIT_SCRIPT"
    if [ ! -f "$INIT_SRC" ]; then
        log_debug "ERROR: Init script not found: $INIT_SRC"
        LOG "red" "Init script not found!"
        exit 1
    fi
    sed "s|^RECON_DB_EXPLORER_DIR=.*|RECON_DB_EXPLORER_DIR=\"$SCRIPT_DIR\"|" "$INIT_SRC" > "$INIT_SCRIPT"
    chmod +x "$INIT_SCRIPT"

    log_debug "Enabling init script"
    "$INIT_SCRIPT" enable
    enable_result=$?
    log_debug "Enable result: $enable_result"

    log_debug "Starting init script"
    "$INIT_SCRIPT" start
    start_result=$?
    log_debug "Start result: $start_result"

    sleep 2

    # Verify service is actually running (procd doesn't always create PID files)
    if "$INIT_SCRIPT" running 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$PORT "; then
        log_debug "Service verified running on port $PORT"
    else
        log_debug "ERROR: Service not running on port $PORT"
        LOG "red" "Service failed to start!"
        exit 1
    fi

    PAGER_IP=$(get_pager_ip)
    LOG "green" "Service started!"
    LOG "green" "http://$PAGER_IP:$PORT"
    LOG ""
    LOG "cyan" "Runs in background"
    LOG "cyan" "Re-run payload to stop"
    sleep 3
    exit 0
fi

LOG "cyan" "Starting foreground mode..."

if ! command -v uhttpd >/dev/null 2>&1; then
    LOG "yellow" "uhttpd required (~28KB)"
    resp=$(CONFIRMATION_DIALOG "Install uhttpd?")
    if user_confirmed "$resp"; then
        LOG "cyan" "Installing uhttpd..."
        opkg update >/dev/null 2>&1
        if ! opkg install uhttpd; then
            LOG "red" "Install failed!"
            exit 1
        fi
    else
        LOG "red" "Cannot run without uhttpd"
        exit 1
    fi
fi

cleanup() {
    LOG "yellow" "Stopping Recon Explorer..."
    [ -f "$PID_FILE" ] && kill $(cat "$PID_FILE") 2>/dev/null
    rm -f "$PID_FILE"
    rm -f /tmp/recon_db_explorer_auth_session
    LOG "cyan" "Recon Explorer stopped."
}
trap cleanup EXIT INT TERM

[ ! -f "$WEB_DIR/index.html" ] && { LOG "red" "Files not found!"; exit 1; }
chmod -R 755 "$WEB_DIR" 2>/dev/null
[ -f "$PID_FILE" ] && kill $(cat "$PID_FILE") 2>/dev/null
rm -f "$PID_FILE"
uhttpd -f -p "$PORT" -h "$WEB_DIR" -c /cgi-bin -T 60 &
echo $! > "$PID_FILE"
sleep 1

PAGER_IP=$(get_pager_ip)
if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    LOG "green" "http://$PAGER_IP:$PORT"
    LOG ""
    LOG "magenta" "Press B to stop"
    while true; do
        BUTTON=$(WAIT_FOR_INPUT)
        if [ "$BUTTON" = "B" ] || [ "$BUTTON" = "Escape" ]; then
            break
        fi
    done
else
    LOG "red" "Failed to start uhttpd!"
    exit 1
fi
