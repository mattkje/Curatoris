# DailyWall

A lightweight macOS menu bar application that automatically updates your desktop wallpaper with beautiful images daily, sourced from DailyWall, Bing, Picsum, Pexels, or your own custom API endpoint.

## Features

- Fetch wallpapers from multiple sources: **DailyWall**, **Bing**, **Picsum**, **Pexels**, and **Custom API endpoints**
- Automatic daily refresh at your chosen time
- Hourly refresh option (for supported sources)
- Refresh on wake from sleep
- Exclude hours — prevent refreshes during a configurable time window
- Wallpaper fill mode control (Fill, Fit, Stretch, Center, Tile)
- Save every wallpaper to a folder automatically
- Wallpaper history with configurable limit
- macOS notification on wallpaper change
- Open at Login support
- Built-in update checker
- Lightweight menu bar application (no dock icon)
- Multi-monitor support — applies wallpaper across all connected displays
- Persistent settings saved between launches

## Installation

Download the latest release from the [Releases](../../releases) page and drag **DailyWall.app** to your Applications folder.

Alternatively, clone the repository and build the project in Xcode.

## Configuration

### DailyWall API Key

The DailyWall source requires a private API key. This key is not publicly available or distributed, which means only the original developer can build and run the app using this source.

### Pexels API Key (optional)

To use the **Pexels** image source, you need a free API key from [pexels.com/api](https://www.pexels.com/api/).

Set the key via an Xcode scheme environment variable or in `Info.plist`:

- **Xcode scheme**: Add `PEXELS_API_KEY` as an environment variable in the scheme's *Run* settings.
- **Info.plist**: Set the value for the `PexelsAPIKey` key.

If no key is configured for either source, it is silently skipped.

## Usage

### First Launch

1. Launch the app from Xcode or your Applications folder
2. You'll see an icon in your menu bar on the right side
3. Click it to open the menu

### Menu Options

**Set Wallpaper Now** — Immediately fetch and set a new wallpaper from the selected source

**Auto Refresh** — Toggle automatic wallpaper updates (checkmark indicates enabled)

**Last Update** — View when your wallpaper was last changed

**Settings…** — Open the Settings window to configure all options

**Check for Updates** — Check GitHub for a newer release

**About DailyWall** — View app info

**Quit** — Close the application

### Settings Window

The Settings window is organised into five panes accessible from the sidebar:

#### General
- **Refresh Schedule** — Enable auto-refresh, toggle hourly refresh, set a manual preferred daily time
- **Behavior** — Refresh on Wake, Exclude Hours (do not refresh during a configurable start–end window)
- **Notifications** — Show a macOS notification each time the wallpaper changes

#### Images
- **Wallpaper Source** — Choose from built-in sources (DailyWall, Bing, Picsum, Pexels) or any custom API endpoint you have added
- **Fill Mode** — Control how the image is scaled to fit your screen (Fill, Fit, Stretch, Center, Tile)
- **Storage** — Optionally save every new wallpaper as a JPEG to a chosen folder

#### History
- View the most recent wallpapers with source and timestamp
- Open any wallpaper URL directly from the list
- Configure how many entries to keep (10, 20, 50, or 100)
- Clear history

#### APIs *(Beta)*
- Add custom image API endpoints by URL and optional display name
- Attach a per-endpoint API key stored securely in Keychain (sent as a Bearer token)
- Supported response formats:
  - Direct image URL redirect
  - JSON object with a `url` key: `{ "url": "https://…" }`
  - JSON array where the first item contains a `url` key

#### Advanced
- **Open at Login** — Launch DailyWall automatically on login
- **History** — Clear the last update record or all wallpaper history

## How It Works

1. **Fetches image URL** — Contacts the selected source's API to retrieve a wallpaper URL
2. **Downloads image** — Saves the full-resolution wallpaper to a temporary folder
3. **Sets wallpaper** — Applies the image to all connected displays via `NSWorkspace`
4. **Saves to folder** — If enabled, copies the wallpaper to your chosen folder as a dated JPEG
5. **Records history** — Appends the URL, source, and timestamp to the wallpaper history
6. **Sends notification** — If enabled, posts a macOS notification confirming the update
7. **Schedules next update** — If auto-refresh is enabled, schedules the next update at the configured time

## Technical Details

### Architecture

- Built with SwiftUI and AppKit
- Runs as an accessory app (menu bar only, no dock icon)
- Uses `NSStatusBar` for menu bar integration
- Leverages `NSWorkspace` for wallpaper setting
- Settings presented in a `NavigationSplitView`-based window

### Data Storage

Settings are persisted using `UserDefaults`:

| Key | Description |
|-----|-------------|
| `autoRefreshEnabled` | Auto-refresh toggle state |
| `refreshTime` | Preferred daily refresh time (HH:MM, default: `08:00`) |
| `everyHourEnabled` | Refresh every hour instead of at a fixed daily time |
| `manualRefreshTimeEnabled` | Whether to use the manually configured refresh time |
| `imageSource` | Selected image source (raw string value or custom URL) |
| `lastUpdateTime` | Timestamp of last wallpaper update |
| `refreshOnWake` | Refresh wallpaper when the Mac wakes from sleep |
| `notifyOnUpdate` | Post a notification on each wallpaper change |
| `saveToFolder` | Save each wallpaper to a local folder |
| `saveFolder` | Path to the save folder |
| `excludeHoursEnabled` | Enable the excluded-hours window |
| `excludeHourStart` | Start of the excluded-hours window (default: 22) |
| `excludeHourEnd` | End of the excluded-hours window (default: 7) |
| `wallpaperFillMode` | Fill mode label (default: `Fill`) |
| `historyLimit` | Maximum number of history entries to keep (default: 20) |
| `wallpaperHistory` | JSON-encoded array of `WallpaperHistoryEntry` |
| `customSourcesV2` | JSON-encoded array of custom API `CustomSource` objects |
| `openAtLogin` | Launch at login toggle state |

API keys for custom endpoints are stored in the macOS **Keychain** under the service `com.dailywall.apikeys`.

### Network

| Source | Endpoint |
|--------|----------|
| DailyWall | `https://dailywall.mattikjellstadli.com/api/daily-wall` |
| Bing | `https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1` |
| Picsum | `https://picsum.photos/3840/2160` |
| Pexels | `https://api.pexels.com/v1/search` |
| Custom | User-supplied HTTPS endpoint |

Requires internet connectivity. DailyWall and Pexels endpoints require an `Authorization: Bearer <key>` header.

### Permissions

- **Network** — To fetch wallpapers from the selected image source
- **System Events** — To update the desktop wallpaper (configured via entitlements)
- **Notifications** — To post wallpaper-change notifications (requested at launch)

## License

MIT License — see the LICENSE file for details.

## Contributing

Contributions are welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests

## Support

For issues, feature requests, or questions, please open an issue on GitHub.
