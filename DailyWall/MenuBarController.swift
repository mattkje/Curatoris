import SwiftUI
import Combine
import Security

@MainActor
class MenuBarController: NSObject, ObservableObject {

    enum BuiltInSource: String, CaseIterable {
        case dailywall = "DailyWall"
        case bing   = "Bing (Only 1080p)"
        case picsum = "Picsum"
        case pexels = "Pexels"
    }

    @Published var autoRefreshEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoRefreshEnabled, forKey: "autoRefreshEnabled")
            updateMenuBar()
            if autoRefreshEnabled { scheduleRefresh() } else { refreshTimer?.invalidate(); refreshTimer = nil }
        }
    }
    @Published var refreshTime: String {
        didSet {
            UserDefaults.standard.set(refreshTime, forKey: "refreshTime")
            updateMenuBar()
            if autoRefreshEnabled { scheduleRefresh() }
        }
    }
    @Published var lastUpdateTime: Date? {
        didSet {
            if let date = lastUpdateTime { UserDefaults.standard.set(date, forKey: "lastUpdateTime") }
        }
    }
    @Published var imageSourceSelection: String {
        didSet {
            UserDefaults.standard.set(imageSourceSelection, forKey: "imageSource")
            updateMenuBar()
        }
    }
    @Published var everyHourEnabled: Bool {
        didSet {
            UserDefaults.standard.set(everyHourEnabled, forKey: "everyHourEnabled")
            updateMenuBar()
            if autoRefreshEnabled { scheduleRefresh() }
        }
    }

    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private let wallpaperManager = WallpaperManager()
    private let sourceProvider   = WallpaperSourceProvider()

    override init() {
        self.autoRefreshEnabled   = UserDefaults.standard.bool(forKey: "autoRefreshEnabled")
        self.refreshTime          = UserDefaults.standard.string(forKey: "refreshTime") ?? "08:00"
        self.lastUpdateTime       = UserDefaults.standard.object(forKey: "lastUpdateTime") as? Date
        self.everyHourEnabled     = UserDefaults.standard.bool(forKey: "everyHourEnabled")
        self.imageSourceSelection = UserDefaults.standard.string(forKey: "imageSource") ?? BuiltInSource.bing.rawValue

        super.init()
        DispatchQueue.main.async {
            self.setupMenuBar()
            if self.autoRefreshEnabled { self.scheduleRefresh() }
        }
    }
    
    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = item
        guard let button = item.button else { return }
        button.image = NSImage(named: "MenuBarIcon")
        button.image?.isTemplate = true
        updateMenuBar()
    }

    private func loadCustomSources() -> [CustomSource] {
        if let data = UserDefaults.standard.data(forKey: "customSourcesV2"),
           let decoded = try? JSONDecoder().decode([CustomSource].self, from: data) {
            return decoded
        }
        if let legacy = UserDefaults.standard.stringArray(forKey: "customSources") {
            return legacy.map { CustomSource(url: $0, label: "") }
        }
        return []
    }

    private func updateMenuBar() {
        guard let statusItem = self.statusItem else { return }
        let menu = NSMenu()

        let setItem = NSMenuItem(title: "Set Wallpaper Now", action: #selector(setWallpaper), keyEquivalent: "w")
        setItem.target = self
        menu.addItem(setItem)

        menu.addItem(.separator())

        let autoTitle = autoRefreshEnabled ? "✓ Auto Refresh" : "Auto Refresh"
        let autoItem = NSMenuItem(title: autoTitle, action: #selector(toggleAutoRefresh), keyEquivalent: "")
        autoItem.target = self
        menu.addItem(autoItem)

        let timeSubmenu = NSMenu()
        let hours = (0..<24).map { String(format: "%02d:00", $0) }
        for time in hours {
            let t = NSMenuItem(title: time, action: #selector(setRefreshTime(_:)), keyEquivalent: "")
            t.target = self
            t.state = (!everyHourEnabled && time == refreshTime) ? .on : .off
            timeSubmenu.addItem(t)
        }
        timeSubmenu.addItem(.separator())
        let everyHourTitle = everyHourEnabled ? "✓ Every Hour" : "Every Hour"
        let everyHourItem = NSMenuItem(title: everyHourTitle, action: #selector(toggleEveryHour), keyEquivalent: "")
        everyHourItem.target = self
        timeSubmenu.addItem(everyHourItem)

        let timeItem = NSMenuItem(title: "Refresh Time", action: nil, keyEquivalent: "")
        timeItem.submenu = timeSubmenu
        menu.addItem(timeItem)

        let sourceSubmenu = NSMenu()

        for source in BuiltInSource.allCases {
            let item = NSMenuItem(title: source.rawValue, action: #selector(setImageSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source.rawValue
            item.state = (source.rawValue == imageSourceSelection) ? .on : .off
            sourceSubmenu.addItem(item)
        }

        let customs = loadCustomSources()
        if !customs.isEmpty {
            sourceSubmenu.addItem(.separator())
            for custom in customs {
                let item = NSMenuItem(title: custom.displayName, action: #selector(setImageSource(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = custom.url
                item.state = (custom.url == imageSourceSelection) ? .on : .off
                if KeychainHelper.load(for: custom.url) != nil {
                    item.title = "\(custom.displayName) 🔑"
                }
                sourceSubmenu.addItem(item)
            }
        }

        let sourceItem = NSMenuItem(title: "Image Source", action: nil, keyEquivalent: "")
        sourceItem.submenu = sourceSubmenu
        menu.addItem(sourceItem)

        menu.addItem(.separator())

        let lastUpdateTitle: String
        if let last = lastUpdateTime {
            let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
            lastUpdateTitle = "Last Update: \(f.string(from: last))"
        } else {
            lastUpdateTitle = "Last Update: Never"
        }
        let lastItem = NSMenuItem(title: lastUpdateTitle, action: nil, keyEquivalent: "")
        lastItem.isEnabled = false
        menu.addItem(lastItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "s")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        updatesItem.image = NSImage(systemSymbolName: "arrow.clockwise.circle", accessibilityDescription: nil)
        menu.addItem(updatesItem)

        let aboutItem = NSMenuItem(title: "About DailyWall", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }
    
    @objc private func toggleAutoRefresh() { autoRefreshEnabled.toggle() }
    @objc private func setRefreshTime(_ sender: NSMenuItem) { everyHourEnabled = false; refreshTime = sender.title }
    @objc private func toggleEveryHour() { everyHourEnabled.toggle() }

    @objc private func setImageSource(_ sender: NSMenuItem) {
        guard let selected = sender.representedObject as? String else { return }
        imageSourceSelection = selected
    }

    @objc private func setWallpaper() {
        Task { @MainActor in
            do {
                let source = sourceProvider.source(forSelectionKey: imageSourceSelection)
                guard let imageURL = try await source.fetchImageURL() else { return }
                let localPath = try await wallpaperManager.downloadImage(from: imageURL)
                try wallpaperManager.setDesktopWallpaper(to: localPath)
                self.lastUpdateTime = Date()
                updateMenuBar()
            } catch {
                print("Error setting wallpaper: \(error)")
            }
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func openSettings() { SettingsWindowController.shared.showWindow() }

    private func scheduleRefresh() {
        refreshTimer?.invalidate(); refreshTimer = nil
        let calendar = Calendar.current
        let now = Date()

        if everyHourEnabled {
            var comps = calendar.dateComponents([.year, .month, .day, .hour], from: now)
            comps.minute = 0; comps.second = 0
            let startOfHour = calendar.date(from: comps) ?? now
            var next = startOfHour
            if next <= now { next = calendar.date(byAdding: .hour, value: 1, to: startOfHour) ?? now.addingTimeInterval(3600) }
            refreshTimer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSinceNow, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.setWallpaper(); self?.scheduleRefresh() }
            }
            return
        }

        let parts = refreshTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        var next = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now) ?? now
        if next <= now { next = calendar.date(byAdding: .day, value: 1, to: next) ?? now.addingTimeInterval(86400) }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.setWallpaper(); self?.scheduleRefresh() }
        }
    }

    @objc private func checkForUpdates() {
        Task { @MainActor in
            guard let apiURL = URL(string: "https://api.github.com/repos/mattkje/DailyWall/releases/latest") else { return }
            struct Release: Decodable { let tag_name: String; let html_url: String }

            func normalize(_ v: String) -> String {
                var s = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
                return s
            }
            func isNewer(_ lhs: String, than rhs: String) -> Bool {
                func parts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0) ?? 0 } }
                let l = parts(lhs), r = parts(rhs)
                for i in 0..<max(l.count, r.count) {
                    let li = i < l.count ? l[i] : 0, ri = i < r.count ? r[i] : 0
                    if li != ri { return li > ri }
                }
                return false
            }

            do {
                var req = URLRequest(url: apiURL)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw NSError(domain: "UpdateCheck", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "GitHub API returned status \(http.statusCode)"])
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latest  = normalize(release.tag_name)
                let current = normalize(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
                let alert = NSAlert()
                if isNewer(latest, than: current) {
                    alert.messageText     = "Update Available"
                    alert.informativeText = "Version \(latest) is available. You are on \(current)."
                    alert.addButton(withTitle: "Open Release Page")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: release.html_url) {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    alert.messageText     = "You're Up to Date"
                    alert.informativeText = "You are running the latest version (\(current))."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            } catch {
                let alert = NSAlert()
                alert.messageText     = "Update Check Failed"
                alert.informativeText = "Could not check for updates.\n\(error.localizedDescription)"
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc private func showAbout() {
        AboutWindowController.shared.showWindow()
    }
}

protocol WallpaperSource {
    func fetchImageURL() async throws -> URL?
}

struct WallpaperSourceProvider {
    /// `selectionKey` is the rawValue for built-ins, or the URL string for custom sources.
    func source(forSelectionKey key: String) -> WallpaperSource {
        switch MenuBarController.BuiltInSource(rawValue: key) {
        case .dailywall: return DailyWallSource()
        case .bing:   return BingSource()
        case .picsum: return PicsumSource()
        case .pexels: return PexelsSource()
        case nil:     return CustomURLSource(urlString: key)
        }
    }
}

struct BingSource: WallpaperSource {
    func fetchImageURL() async throws -> URL? {
        let url = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let images = json?["images"] as? [[String: Any]],
              let urlPath = images.first?["url"] as? String else { return nil }
        return URL(string: "https://www.bing.com\(urlPath)")
    }
}

struct PicsumSource: WallpaperSource {
    func fetchImageURL() async throws -> URL? {
        URL(string: "https://picsum.photos/3840/2160")
    }
}

struct DailyWallSource: WallpaperSource {
    private func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["DAILY_WALL_API_KEY"], !env.isEmpty { return env }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "DailyWallAPIKey") as? String, !plist.isEmpty { return plist }
        return nil
    }
    
    func fetchImageURL() async throws -> URL? {
        guard let apiKey = apiKey() else { return nil }
        var comps = URLComponents(string: "https://dailywall.mattikjellstadli.com/api/daily-wall")!
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let str = json["url"] as? String {
            return URL(string: str)
        }
        return nil
    }
}

struct PexelsSource: WallpaperSource {
    private func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["PEXELS_API_KEY"], !env.isEmpty { return env }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "PexelsAPIKey") as? String, !plist.isEmpty { return plist }
        return nil
    }

    func fetchImageURL() async throws -> URL? {
        guard let apiKey = apiKey() else { return nil }
        let queries = ["landscape nature","mountains","ocean","forest","minimal landscape",
                       "abstract gradient","night sky","desert","snow landscape"]
        var comps = URLComponents(string: "https://api.pexels.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "query",       value: queries.randomElement() ?? "landscape"),
            URLQueryItem(name: "per_page",    value: "40"),
            URLQueryItem(name: "orientation", value: "landscape"),
            URLQueryItem(name: "size",        value: "large")
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        guard let json   = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let photos = json["photos"] as? [[String: Any]] else { return nil }
        let filtered = photos.filter { ($0["people"] as? Int ?? 0) == 0 }
        guard let photo = (filtered.isEmpty ? photos : filtered).randomElement(),
              let src = photo["src"] as? [String: Any] else { return nil }
        if let str = src["original"] as? String, let url = URL(string: str) { return url }
        for key in ["large2x", "large", "landscape"] {
            if let str = src[key] as? String, var c = URLComponents(string: str) { c.queryItems = nil; return c.url }
        }
        return nil
    }
}

struct CustomURLSource: WallpaperSource {
    let urlString: String

    func fetchImageURL() async throws -> URL? {
        guard let endpointURL = URL(string: urlString) else { return nil }

        var request = URLRequest(url: endpointURL)

        // Attach API key from Keychain if one is saved for this URL
        if let key = KeychainHelper.load(for: urlString), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        // Try fetching as JSON first; fall back to treating the URL as a direct image link
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
           let contentType = http.value(forHTTPHeaderField: "Content-Type") {

            // Direct image response — URL itself is the image
            if contentType.hasPrefix("image/") {
                return endpointURL
            }

            // JSON response — extract "url" field
            if contentType.contains("json") {
                if let url = extractImageURL(from: data) { return url }
            }
        }

        // Last resort: attempt JSON parse regardless of content-type
        if let url = extractImageURL(from: data) { return url }

        // Fall back to the raw URL (e.g. direct redirect endpoint)
        return endpointURL
    }

    /// Handles both `{"url":"..."}` objects and `[{"url":"..."}]` arrays.
    private func extractImageURL(from data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        func urlFrom(_ dict: [String: Any]) -> URL? {
            if let str = dict["url"] as? String { return URL(string: str) }
            if let str = dict["imageUrl"] as? String { return URL(string: str) }
            if let str = dict["image"] as? String { return URL(string: str) }
            return nil
        }

        if let dict = json as? [String: Any] { return urlFrom(dict) }
        if let arr = json as? [[String: Any]], let first = arr.first { return urlFrom(first) }
        return nil
    }
}
