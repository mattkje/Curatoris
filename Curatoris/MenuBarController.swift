import SwiftUI
import Combine
import Security
import UserNotifications

@MainActor
class MenuBarController: NSObject, ObservableObject {

    enum BuiltInSource: String, CaseIterable {
        case curatoris = "Curatoris"
        case bing      = "Bing (Only 1080p)"
        case picsum    = "Picsum"
        case pexels    = "Pexels"
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
            if autoRefreshEnabled { scheduleRefresh() }
        }
    }
    @Published var lastUpdateTime: Date? {
        didSet {
            if let date = lastUpdateTime {
                UserDefaults.standard.set(date, forKey: "lastUpdateTime")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastUpdateTime")
            }
            updateMenuBar()
        }
    }
    @Published var imageSourceSelection: String {
        didSet {
            UserDefaults.standard.set(imageSourceSelection, forKey: "imageSource")
            if imageSourceSelection == BuiltInSource.curatoris.rawValue {
                curatorisChainDate = today()
            } else {
                curatorisChainDate = nil
            }
            updateMenuBar()
        }
    }
    @Published var everyHourEnabled: Bool {
        didSet {
            UserDefaults.standard.set(everyHourEnabled, forKey: "everyHourEnabled")
            if autoRefreshEnabled { scheduleRefresh() }
        }
    }
    @Published var curatorisChainDate: Date? = nil

    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private let wallpaperManager = WallpaperManager()
    private let sourceProvider   = WallpaperSourceProvider()
    private var defaultsObservers: [NSKeyValueObservation] = []

    private var refreshOnWake: Bool       { UserDefaults.standard.bool(forKey: "refreshOnWake") }
    private var notifyOnUpdate: Bool      { UserDefaults.standard.bool(forKey: "notifyOnUpdate") }
    private var saveToFolder: Bool        { UserDefaults.standard.bool(forKey: "saveToFolder") }
    private var saveFolder: String        { UserDefaults.standard.string(forKey: "saveFolder") ?? "" }
    private var excludeHoursEnabled: Bool { UserDefaults.standard.bool(forKey: "excludeHoursEnabled") }
    private var excludeHourStart: Int     { UserDefaults.standard.object(forKey: "excludeHourStart") as? Int ?? 22 }
    private var excludeHourEnd: Int       { UserDefaults.standard.object(forKey: "excludeHourEnd")   as? Int ?? 7  }
    private var wallpaperFillMode: String { UserDefaults.standard.string(forKey: "wallpaperFillMode") ?? "Fill" }
    private var historyLimit: Int         { UserDefaults.standard.object(forKey: "historyLimit") as? Int ?? 20 }

    override init() {
        self.autoRefreshEnabled   = UserDefaults.standard.bool(forKey: "autoRefreshEnabled")
        self.refreshTime          = UserDefaults.standard.string(forKey: "refreshTime") ?? "08:00"
        self.lastUpdateTime       = UserDefaults.standard.object(forKey: "lastUpdateTime") as? Date
        self.everyHourEnabled     = UserDefaults.standard.bool(forKey: "everyHourEnabled")
        self.imageSourceSelection = UserDefaults.standard.string(forKey: "imageSource") ?? BuiltInSource.curatoris.rawValue
        self.curatorisChainDate   = nil
        super.init()
        if self.imageSourceSelection == BuiltInSource.curatoris.rawValue {
            self.curatorisChainDate = today()
        }
        DispatchQueue.main.async {
            self.setupMenuBar()
            self.requestNotificationPermissionIfNeeded()
            self.checkForUpdates(silentIfUpToDate: true)
            self.startObservers()
            if self.autoRefreshEnabled && self.needsDailyUpdate() { self.setWallpaper() }
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

    private func updateMenuBar() {
        guard let statusItem = self.statusItem else { return }
        let menu = NSMenu()

        let setItem = NSMenuItem(title: "Set Wallpaper Now", action: #selector(setWallpaper(_:)), keyEquivalent: "w")
        setItem.target = self
        menu.addItem(setItem)

        let autoItem = NSMenuItem(
            title: autoRefreshEnabled ? "✓ Auto Refresh" : "Auto Refresh",
            action: #selector(toggleAutoRefresh),
            keyEquivalent: ""
        )
        autoItem.target = self
        menu.addItem(autoItem)
        
        // Only show previous/next if Curatoris is selected
        if isCuratorisSourceSelected() {
            let previousItem = NSMenuItem(title: "Previous", action: #selector(previous(_:)), keyEquivalent: "")
            previousItem.target = self
            previousItem.isEnabled = curatorisChainDate != nil && curatorisChainDate! > Date(timeIntervalSince1970: 0)
            menu.addItem(previousItem)

            let nextItem = NSMenuItem(title: "Next", action: #selector(next(_:)), keyEquivalent: "")
            nextItem.target = self
            if let chainDate = curatorisChainDate {
                let today = self.today()
                nextItem.isEnabled = Calendar.current.compare(chainDate, to: today, toGranularity: .day) == .orderedAscending
            } else {
                nextItem.isEnabled = false
            }
            menu.addItem(nextItem)
        }

        menu.addItem(.separator())

        let lastItem = NSMenuItem(title: lastUpdateLabel, action: nil, keyEquivalent: "")
        lastItem.isEnabled = false
        menu.addItem(lastItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdatesTapped), keyEquivalent: "")
        updatesItem.target = self
        updatesItem.image = NSImage(systemSymbolName: "arrow.clockwise.circle", accessibilityDescription: nil)
        menu.addItem(updatesItem)

        let aboutItem = NSMenuItem(title: "About Curatoris", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private var lastUpdateLabel: String {
        guard let last = lastUpdateTime else { return "Last Update: Never" }
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return "Last Update: \(f.string(from: last))"
    }

    @objc private func toggleAutoRefresh()     { autoRefreshEnabled.toggle() }
    @objc private func quitApp()               { NSApp.terminate(nil) }
    @objc private func openSettings()          { SettingsWindowController.shared.showWindow() }
    @objc private func showAbout()             { AboutWindowController.shared.showWindow() }
    @objc private func checkForUpdatesTapped() { checkForUpdates(silentIfUpToDate: false) }

    @objc func setWallpaper(_ sender: AnyObject?) {
        if isCuratorisSourceSelected() {
            resetCuratorisChainToToday()
            setWallpaperForCuratorisChainDate()
        } else {
            setWallpaper()
        }
    }
    @objc func setWallpaper(overrideDate: Date? = nil) {
        guard !isInExcludedHours() else { return }
        Task { @MainActor in
            do {
                let currentSource = UserDefaults.standard.string(forKey: "imageSource")
                    ?? BuiltInSource.curatoris.rawValue
                let source = sourceProvider.source(forSelectionKey: currentSource)
                let imageURL: URL?
                let usedDate = overrideDate
                if let curatorisSource = source as? CuratorisSource {
                    let dateString: String? = {
                        guard let date = usedDate else { return nil }
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        return formatter.string(from: date)
                    }()
                    imageURL = try await curatorisSource.fetchImageURL(for: dateString)
                } else {
                    imageURL = try await source.fetchImageURL()
                }
                guard let imageURL else { return }
                let localPath = try await wallpaperManager.downloadImage(from: imageURL)
                let fillMode  = nsWorkspaceFillMode(for: wallpaperFillMode)
                try wallpaperManager.setDesktopWallpaper(to: localPath, fillMode: fillMode)
                // Only update lastUpdateTime if not navigating history
                if overrideDate == nil {
                    self.lastUpdateTime = Date()
                }
                appendHistory(imageURL: imageURL.absoluteString, source: currentSource)
                saveWallpaperToFolder(at: localPath)
                sendUpdateNotificationIfEnabled()
            } catch {
                print("Error setting wallpaper: \(error)")
            }
        }
    }

    // --- CLEANUP: Remove debug logs from Curatoris navigation and API ---
    private func setWallpaperForCuratorisChainDate() {
        guard let date = curatorisChainDate else { return }
        Task { @MainActor in
            do {
                let source = CuratorisSource()
                let dateString = formattedChainDate()
                let imageURL = try await source.fetchImageURL(for: dateString)
                guard let imageURL else { return }
                let localPath = try await wallpaperManager.downloadImage(from: imageURL)
                let fillMode  = nsWorkspaceFillMode(for: wallpaperFillMode)
                try wallpaperManager.setDesktopWallpaper(to: localPath, fillMode: fillMode)
                self.lastUpdateTime = date
                appendHistory(imageURL: imageURL.absoluteString, source: BuiltInSource.curatoris.rawValue)
                saveWallpaperToFolder(at: localPath)
                sendUpdateNotificationIfEnabled()
            } catch {
                // Optionally log error in production
            }
        }
    }

    @objc func previous(_ sender: AnyObject?) {
        guard isCuratorisSourceSelected(), let chainDate = curatorisChainDate else { return }
        let prev = Calendar.current.date(byAdding: .day, value: -1, to: chainDate)!
        curatorisChainDate = prev
        autoRefreshEnabled = false
        setWallpaperForCuratorisChainDate()
    }

    @objc func next(_ sender: AnyObject?) {
        guard isCuratorisSourceSelected(), let chainDate = curatorisChainDate else { return }
        let today = self.today()
        let next = Calendar.current.date(byAdding: .day, value: 1, to: chainDate)!
        if Calendar.current.compare(next, to: today, toGranularity: .day) != .orderedDescending {
            curatorisChainDate = next
            setWallpaperForCuratorisChainDate()
        }
    }

    private func startObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.refreshOnWake || (self.autoRefreshEnabled && self.needsDailyUpdate()) {
                    self.setWallpaper()
                }
                if self.autoRefreshEnabled { self.scheduleRefresh() }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.autoRefreshEnabled && self.needsDailyUpdate() { self.setWallpaper() }
            }
        }

        let ud = UserDefaults.standard
        defaultsObservers = [
            ud.observe(\.imageSource, options: [.new]) { [weak self] _, change in
                guard let self, let val = change.newValue else { return }
                Task { @MainActor in
                    if self.imageSourceSelection != val { self.imageSourceSelection = val }
                }
            },
            ud.observe(\.autoRefreshEnabled, options: [.new]) { [weak self] _, change in
                guard let self, let val = change.newValue else { return }
                Task { @MainActor in
                    if self.autoRefreshEnabled != val { self.autoRefreshEnabled = val }
                }
            },
            ud.observe(\.everyHourEnabled, options: [.new]) { [weak self] _, change in
                guard let self, let val = change.newValue else { return }
                Task { @MainActor in
                    if self.everyHourEnabled != val { self.everyHourEnabled = val }
                }
            },
            ud.observe(\.refreshTime, options: [.new]) { [weak self] _, change in
                guard let self, let val = change.newValue else { return }
                Task { @MainActor in
                    if self.refreshTime != val { self.refreshTime = val }
                }
            },
        ]
    }

    private func isInExcludedHours() -> Bool {
        guard excludeHoursEnabled else { return false }
        let hour  = Calendar.current.component(.hour, from: Date())
        let start = excludeHourStart
        let end   = excludeHourEnd
        return start <= end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    private func appendHistory(imageURL: String, source: String) {
        let entry = WallpaperHistoryEntry(url: imageURL, setAt: Date(), source: source)
        var history: [WallpaperHistoryEntry]
        if let data = UserDefaults.standard.data(forKey: "wallpaperHistory"),
           let decoded = try? JSONDecoder().decode([WallpaperHistoryEntry].self, from: data) {
            history = decoded
        } else {
            history = []
        }
        history.append(entry)
        if history.count > historyLimit { history = Array(history.suffix(historyLimit)) }
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: "wallpaperHistory")
        }
    }

    private func saveWallpaperToFolder(at localPath: String) {
        guard saveToFolder, !saveFolder.isEmpty else { return }
        let src      = URL(fileURLWithPath: localPath)
        let folder   = URL(fileURLWithPath: saveFolder)
        let f        = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dest     = folder.appendingPathComponent("curatoris_\(f.string(from: Date())).jpg")
        try? FileManager.default.copyItem(at: src, to: dest)
    }

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func sendUpdateNotificationIfEnabled() {
        guard notifyOnUpdate else { return }
        let content       = UNMutableNotificationContent()
        content.title     = "Wallpaper Updated"
        content.body      = "Your wallpaper has been refreshed by Curatoris."
        let request       = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func nsWorkspaceFillMode(for label: String) -> NSImageScaling {
        switch label {
        case "Fit":     return .scaleProportionallyUpOrDown
        case "Stretch": return .scaleAxesIndependently
        case "Center":  return .scaleNone
        default:        return .scaleProportionallyUpOrDown
        }
    }

    private func needsDailyUpdate() -> Bool {
        guard let last = lastUpdateTime else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate(); refreshTimer = nil
        let calendar = Calendar.current
        let now      = Date()

        if everyHourEnabled {
            var comps    = calendar.dateComponents([.year, .month, .day, .hour], from: now)
            comps.minute = 0; comps.second = 0
            let startOfHour = calendar.date(from: comps) ?? now
            var next        = startOfHour
            if next <= now { next = calendar.date(byAdding: .hour, value: 1, to: startOfHour) ?? now.addingTimeInterval(3600) }
            refreshTimer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSinceNow, repeats: false) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.setWallpaper()
                    self.scheduleRefresh()
                }
            }
            return
        }

        let parts = refreshTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        var next = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now) ?? now
        if next <= now {
            if needsDailyUpdate() { Task { @MainActor in self.setWallpaper() } }
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? now.addingTimeInterval(86400)
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.setWallpaper()
                self.scheduleRefresh()
            }
        }
    }

    @objc private func checkForUpdates(silentIfUpToDate: Bool = false) {
        Task { @MainActor in
            guard let apiURL = URL(string: "https://api.github.com/repos/mattkje/Curatoris/releases/latest") else { return }
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
                                  userInfo: [NSLocalizedDescriptionKey: "GitHub API returned \(http.statusCode)"])
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latest  = normalize(release.tag_name)
                let current = normalize(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
                if isNewer(latest, than: current) {
                    let alert = NSAlert()
                    alert.messageText     = "Update Available"
                    alert.informativeText = "Version \(latest) is available. You are on \(current)."
                    alert.addButton(withTitle: "Open Release Page")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: release.html_url) {
                        NSWorkspace.shared.open(url)
                    }
                } else if !silentIfUpToDate {
                    let alert = NSAlert()
                    alert.messageText     = "You're Up to Date"
                    alert.informativeText = "You are running the latest version (\(current))."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            } catch {
                if !silentIfUpToDate {
                    let alert = NSAlert()
                    alert.messageText     = "Update Check Failed"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    private func isCuratorisSourceSelected() -> Bool {
        imageSourceSelection == BuiltInSource.curatoris.rawValue
    }

    private func today() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func formattedChainDate() -> String? {
        guard let date = curatorisChainDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func resetCuratorisChainToToday() {
        curatorisChainDate = today()
    }
}

extension UserDefaults {
    @objc dynamic var imageSource: String        { string(forKey: "imageSource") ?? "" }
    @objc dynamic var autoRefreshEnabled: Bool   { bool(forKey: "autoRefreshEnabled") }
    @objc dynamic var everyHourEnabled: Bool     { bool(forKey: "everyHourEnabled") }
    @objc dynamic var refreshTime: String        { string(forKey: "refreshTime") ?? "" }
}

protocol WallpaperSource {
    func fetchImageURL() async throws -> URL?
}

struct WallpaperSourceProvider {
    func source(forSelectionKey key: String) -> WallpaperSource {
        switch MenuBarController.BuiltInSource(rawValue: key) {
        case .curatoris: return CuratorisSource()
        case .bing:      return BingSource()
        case .picsum:    return PicsumSource()
        case .pexels:    return PexelsSource()
        case nil:        return CustomURLSource(urlString: key)
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

struct CuratorisSource: WallpaperSource {
    private func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["CURATORIS_API_KEY"], !env.isEmpty { return env }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "CuratorisAPIKey") as? String, !plist.isEmpty { return plist }
        return nil
    }

    // Accepts an optional date string in yyyy-MM-dd format
    func fetchImageURL(for date: String? = nil) async throws -> URL? {
        guard let apiKey = apiKey() else { return nil }
        var comps: URLComponents
        if let date = date {
            comps = URLComponents(string: "https://curatoris.mattikjellstadli.com/api/curatoris/\(date)")!
        } else {
            comps = URLComponents(string: "https://curatoris.mattikjellstadli.com/api/curatoris")!
        }
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let str = json["url"] as? String { return URL(string: str) }
        return nil
    }

    func fetchImageURL() async throws -> URL? {
        return try await fetchImageURL(for: nil)
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
        let queries = ["landscape nature", "mountains", "ocean", "forest", "minimal landscape",
                       "abstract gradient", "night sky", "desert", "snow landscape"]
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
        if let key = KeychainHelper.load(for: urlString), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           let contentType = http.value(forHTTPHeaderField: "Content-Type") {
            if contentType.hasPrefix("image/") { return endpointURL }
            if contentType.contains("json"), let url = extractImageURL(from: data) { return url }
        }
        if let url = extractImageURL(from: data) { return url }
        return endpointURL
    }

    private func extractImageURL(from data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        func urlFrom(_ dict: [String: Any]) -> URL? {
            if let str = dict["url"]      as? String { return URL(string: str) }
            if let str = dict["imageUrl"] as? String { return URL(string: str) }
            if let str = dict["image"]    as? String { return URL(string: str) }
            return nil
        }
        if let dict = json as? [String: Any]                        { return urlFrom(dict) }
        if let arr  = json as? [[String: Any]], let first = arr.first { return urlFrom(first) }
        return nil
    }
}
