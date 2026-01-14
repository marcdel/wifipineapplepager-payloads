# Flock Safety Device Detector

A surveillance device detector for the WiFi Pineapple Pager that monitors for Flock Safety and related surveillance devices via WiFi and Bluetooth.

## Overview

This payload detects nearby Flock Safety surveillance devices by monitoring:
- **WiFi**: Access points with known Flock SSIDs and MAC address prefixes
- **Bluetooth**: BLE and Classic Bluetooth devices with known names and MAC addresses

When a Flock device is detected, you will receive:
- Visual alert on screen
- Red LED flash
- Vibration alert
- Log entry with device details

## Usage

Run the **Flock Detector** payload. You'll see a menu with the following options:

| Option | Description |
|--------|-------------|
| 1) Run in foreground | Scan with live output on screen. Press B to stop. |
| 2) Run in background | Scan silently, logging to file. Returns to menu. |
| 3) Stop background | Stop the background scanner if running. |
| 4) View status | Check if scanner is running and view detection counts. |
| 5) View logs | View the log file (useful after background scanning). |
| 0) Exit | Exit the payload. |

### Foreground Mode

- Scan output appears directly on the Pager screen
- Green LED indicates scanning is active
- Press **B** to stop and return to menu
- Best for active monitoring

### Background Mode

- Scanner runs silently in the background
- Logs written to `/tmp/flock_detector.log`
- You can exit the payload and the scanner continues running
- Use "View logs" or "View status" to check on it later
- Best for passive/long-term monitoring

## Detected Device Types

### Flock Safety Devices
- Flock WiFi cameras/readers
- FS Ext Battery devices (extended battery packs)

### Related Surveillance Devices
- Penguin surveillance devices
- Pigvision surveillance systems

## Detection Methods

### WiFi Detection
- SSID pattern matching (flock, FS Ext Battery, Penguin, Pigvision)
- MAC address prefix (OUI) matching against known Flock hardware

### Bluetooth Detection
- BLE device name matching
- Classic Bluetooth inquiry
- MAC address prefix matching

## Known MAC Prefixes

The detector monitors for these OUI prefixes:

**FS Ext Battery:**
- 58:8e:81, cc:cc:cc, ec:1b:bd, 90:35:ea, 04:0d:84
- f0:82:c0, 1c:34:f1, 38:5b:44, 94:34:69, b4:e3:f9

**Flock WiFi:**
- 70:c9:4e, 3c:91:80, d8:f3:bc, 80:30:49, 14:5a:fc
- 74:4c:a1, 08:3a:88, 9c:2f:9d, 94:08:53, e4:aa:ea

## File Locations

### Payload Files
```
flock_detector/
├── payload.sh           # Main payload with menu
├── scanner.sh           # Scanner logic
├── flock_signatures.sh  # Detection signatures database
├── config.sh            # Configuration settings
└── README.md
```

### Runtime Files (in /tmp)
```
/tmp/flock_detector.pid         # PID file (when running in background)
/tmp/flock_detector.log         # Log messages (when running in background)
/tmp/flock_seen_devices.txt     # Deduplication tracking
```

### Loot Files
Detected device info is saved as JSON to `/root/loot/flock_detector/detections_<timestamp>.json`

## Configuration

Edit `config.sh` to customize these settings:

| Setting | Default | Description |
|---------|---------|-------------|
| WIFI_SCAN_DURATION | 10s | Duration of each WiFi scan |
| BT_SCAN_DURATION | 10s | Duration of each Bluetooth scan |
| SCAN_INTERVAL | 5s | Pause between scan cycles |
| ALERT_COOLDOWN | 300s | Don't re-alert same device within this time |

## Viewing Logs

From the payload menu, select option **5) View logs** to see the log file.

Or via command line:
```bash
# View full log
cat /tmp/flock_detector.log

# View only detections
grep "\[DETECTION\]" /tmp/flock_detector.log

# Follow log in real-time
tail -f /tmp/flock_detector.log
```

## Credits

Detection signatures sourced from:
- [Flock You](https://github.com/colonelpanichacks/flock-you) by ColonelPanicHacks
- [NyanBOX](https://github.com/jbohack/nyanBOX) by jbohack

## Disclaimer

This tool is for educational and research purposes blah blah blah. Use responsibly and in accordance with applicable laws and regulations.