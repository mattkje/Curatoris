//
//  WallpaperManager.swift
//  DailyWall
//
//  Created by Matti Kjellstadli on 01/04/2026.
//

import Foundation
import AppKit

final class WallpaperManager {
    func downloadImage(from url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dailywall_\(UUID().uuidString).jpg")
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
    }

    func setDesktopWallpaper(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }
}
