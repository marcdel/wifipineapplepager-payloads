#!/bin/bash
# Flock Detector Configuration
# Edit these values to customize scanner behavior

# Scan durations (seconds)
WIFI_SCAN_DURATION=5
BT_SCAN_DURATION=5

# Time between scan cycles (seconds)
SCAN_INTERVAL=30

# Alert cooldown - don't re-alert same device within this time (seconds)
ALERT_COOLDOWN=300  # 5 minutes

# Loot directory for JSON detections
LOOT_DIR="/root/loot/flock_detector"

# Debug mode - show extra debug messages (0=off, 1=on)
DEBUG_MODE=1