// Refactor Notes

This refactor splits responsibilities previously contained in `MenuBarController.swift` into distinct components to improve readability and maintainability:

- WallpaperSource protocol and concrete sources: `BingSource`, `PicsumSource`, `PexelsSource`.
- WallpaperManager for downloading and setting wallpapers.
- MenuBarController now orchestrates UI, scheduling, and uses the above components.

Behavior remains the same. You can further move the types into their own files later if desired.
