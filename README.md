# Curatoris

A menu bar app for macOS that automatically updates your desktop wallpaper daily from Curatoris, Bing, Picsum, Pexels, or custom API endpoints.

## Features

- Multiple wallpaper sources (Curatoris, Bing, Picsum, Pexels, custom API)
- Automatic daily or hourly refresh
- Manual refresh anytime
- Refresh on wake from sleep
- Exclude hours (prevent refresh during certain times)
- Wallpaper fill modes (Fill, Fit, Stretch, Center, Tile)
- Save wallpapers to a folder
- Wallpaper history with configurable limit
- Notifications on wallpaper change
- Multi-monitor support
- Open at login
- Built-in update checker

## Installation

Download from Releases and drag Curatoris.app to Applications, or build from source with Xcode.

## Setup

### Curatoris API Key

The Curatoris source requires a private API key. Only the original developer can use this source.

### Pexels API Key (optional)

Get a free API key from pexels.com/api. Set it in Xcode as an environment variable `PEXELS_API_KEY` or in Info.plist under `PexelsAPIKey`.

## Usage

Click the menu bar icon to access:
- Set Wallpaper Now - fetch and apply a new wallpaper immediately
- Auto Refresh - toggle automatic updates
- Last Update - view when wallpaper last changed
- Settings - configure all options
- Check for Updates - check for new releases
- Quit - close the app

## Settings

**General**: Refresh schedule, refresh on wake, exclude hours, notifications

**Images**: Choose source, select fill mode, set storage folder

**History**: View and manage wallpaper history

**APIs**: Add custom API endpoints with optional keys

**Advanced**: Open at login, clear history

## How It Works

1. Fetch image URL from selected source
2. Download the wallpaper
3. Apply to all displays
4. Optionally save to folder
5. Add to history
6. Send notification if enabled
7. Schedule next update

## Supported Sources

| Source | Endpoint |
|--------|----------|
| Curatoris | https://curatoris.mattikjellstadli.com/api/daily-wall |
| Bing | https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1 |
| Picsum | https://picsum.photos/3840/2160 |
| Pexels | https://api.pexels.com/v1/search |
| Custom | User-supplied endpoint |

## License

MIT License
