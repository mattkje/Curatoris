import Foundation
import AppKit

final class WallpaperManager {
            static func shouldUseOsascript() -> Bool {
                return UserDefaults.standard.bool(forKey: "useOsascriptForWallpaper")
            }

            func setWallpaperWithOsascript(to path: String) throws {
                let script = "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"\(path)\""
                let process = Process()
                process.launchPath = "/usr/bin/osascript"
                process.arguments = ["-e", script]
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    throw NSError(domain: "WallpaperManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "osascript failed to set wallpaper"])
                }
            }
    func downloadImage(from url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("curatoris_\(UUID().uuidString).jpg")
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
    }

    func setDesktopWallpaper(to path: String, fillMode: NSImageScaling = .scaleProportionallyUpOrDown) throws {
        if WallpaperManager.shouldUseOsascript() {
            try setWallpaperWithOsascript(to: path)
        } else {
            let url = URL(fileURLWithPath: path)
            // .allowClipping: true + scaleProportionallyUpOrDown = "Fill" (scale to fill, crop edges)
            // Without allowClipping it becomes "Fit" (letterbox).
            let allowClipping = (fillMode == .scaleProportionallyUpOrDown)
            let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                .imageScaling:   fillMode.rawValue,
                .allowClipping:  allowClipping
            ]
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            }
        }
    }
}
