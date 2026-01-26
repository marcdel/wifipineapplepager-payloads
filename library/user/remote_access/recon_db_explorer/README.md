# Recon DB Explorer

Web-based viewer for the recon.db SQLite database with paginated table browsing.

## Features

- **Authentication**: Requires root password to access
- **Table Browser**: View all tables in recon.db with row counts
- **Paginated Data**: Browse large tables with pagination (50 rows per page)

## Usage

1. Run the payload from the device
2. Choose foreground or background (service) mode
3. Access the web interface at `http://<device-ip>:8889`
4. Login with the device's root password
5. Select a table from the sidebar to view its contents

## Database Location

Reads from `/root/recon/recon.db`

## Port

Runs on port **8889** (avoids conflict with Nautilus on 8888)
