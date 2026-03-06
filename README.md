# DailyWall

A lightweight macOS menu bar application that automatically updates your desktop wallpaper with beautiful Bing images daily.

## Features
- Fetch daily wallpapers from Bing
- Automatic daily refresh at your chosen time
- Lightweight menu bar application (no dock icon)

## Installation

There will be downloads available in the release section, but not now


## Usage

### First Launch
1. Launch the app from Xcode or your Applications folder
2. You'll see a photo icon in your menu bar on the right side
3. Click it to open the menu

### Menu Options

**Set Wallpaper Now** — Immediately fetch and set today's Bing wallpaper

**Auto Refresh** — Toggle automatic daily wallpaper updates (checkmark indicates enabled)

**Refresh Time** — Choose what time the wallpaper updates (6 AM to 9 PM):
- 06:00, 07:00, 08:00, 09:00, 10:00, 12:00, 18:00, 21:00

**Last Update** — View when your wallpaper was last changed

**Quit** — Close the application

## How It Works

1. **Fetches from Bing** — Downloads metadata from Bing's daily image API
2. **Downloads Image** — Saves the full-resolution wallpaper to your temp folder
3. **Sets Wallpaper** — Applies the image to all connected displays
4. **Schedules Next Update** — If auto-refresh is enabled, schedules the next update for your chosen time

## Technical Details

### Architecture
- Built with SwiftUI and AppKit
- Runs as an accessory app (menu bar only, no dock icon)
- Uses `NSStatusBar` for menu bar integration
- Leverages `NSWorkspace` for wallpaper setting

### Data Storage
Settings are persisted using `UserDefaults`:
- `autoRefreshEnabled` — Auto-refresh toggle state
- `refreshTime` — Selected refresh time (HH:MM format)
- `lastUpdateTime` — Timestamp of last wallpaper update

### Network
- Fetches metadata from: `https://www.bing.com/HPImageArchive.aspx`
- Downloads images from: `https://www.bing.com`
- Requires internet connectivity

### Permissions
The app requires the following macOS permissions:
- **Network**: To fetch wallpapers from Bing
- **System Events**: To update your desktop wallpaper (configured via entitlements)

## License

MIT License - See LICENSE file for details

## Contributing

Contributions are welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests

## Support

For issues, feature requests, or questions, please open an issue on GitHub.
