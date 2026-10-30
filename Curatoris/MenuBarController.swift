import SwiftUI
import Combine
import Security
import UserNotifications

@MainActor
class MenuBarController: NSObject, ObservableObject {

    enum BuiltInSource: String, CaseIterable {
        case curatoris = "Curatoris"
        case bing      = "Bing"
        case picsum    = "Picsum"
        case pexels    = "Pexels"

        /// Sources that need an API key are hidden when the app was built without one.
        var isAvailable: Bool {
            switch self {
            case .curatoris: return CuratorisAPI.apiKey != nil
            case .pexels:    return PexelsSource.apiKey != nil
            case .bing, .picsum: return true // Bing falls back to bing.com without the Curatoris key
            }
        }

        static var available: [BuiltInSource] { allCases.filter(\.isAvailable) }

        static var defaultSource: BuiltInSource { curatoris.isAvailable ? .curatoris : .bing }

        /// Replaces a stored built-in source whose key is missing with the default; custom URLs pass through.
        static func sanitized(_ selection: String?) -> String {
            guard let selection else { return defaultSource.rawValue }
            if let source = BuiltInSource(rawValue: selection), !source.isAvailable {
                return defaultSource.rawValue
            }
            return selection
        }
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
            if isChainNavigationSourceSelected() {
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
    @Published var curatorisChainDate: Date? = nil {
        didSet { refreshPreviewIfNeeded() }
    }

    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private let wallpaperManager = WallpaperManager()
    private let sourceProvider   = WallpaperSourceProvider()
    private var defaultsObservers: [NSKeyValueObservation] = []
    private var bingArchive: [BingArchiveEntry] = []
    private var bingArchiveFetchedAt: Date?
    private let preview = MenuPreviewModel()
    private var previewKey: String?
    private var isMenuOpen = false
    private var needsMenuRebuild = false

    private var refreshOnWake: Bool       { UserDefaults.standard.bool(forKey: "refreshOnWake") }
    private var notifyOnUpdate: Bool      { UserDefaults.standard.bool(forKey: "notifyOnUpdate") }
    private var saveToFolder: Bool        { UserDefaults.standard.bool(forKey: "saveToFolder") }
    private var saveFolder: String        { UserDefaults.standard.string(forKey: "saveFolder") ?? "" }
    private var excludeHoursEnabled: Bool { UserDefaults.standard.bool(forKey: "excludeHoursEnabled") }
    private var excludeHourStart: Int     { UserDefaults.standard.object(forKey: "excludeHourStart") as? Int ?? 22 }
    private var excludeHourEnd: Int       { UserDefaults.standard.object(forKey: "excludeHourEnd")   as? Int ?? 7  }
    private var historyLimit: Int         { UserDefaults.standard.object(forKey: "historyLimit") as? Int ?? 20 }

    override init() {
        self.autoRefreshEnabled   = UserDefaults.standard.bool(forKey: "autoRefreshEnabled")
        self.refreshTime          = UserDefaults.standard.string(forKey: "refreshTime") ?? "08:00"
        self.lastUpdateTime       = UserDefaults.standard.object(forKey: "lastUpdateTime") as? Date
        self.everyHourEnabled     = UserDefaults.standard.bool(forKey: "everyHourEnabled")
        let storedSource          = UserDefaults.standard.string(forKey: "imageSource")
        let source                = BuiltInSource.sanitized(storedSource)
        if storedSource != source { UserDefaults.standard.set(source, forKey: "imageSource") }
        self.imageSourceSelection = source
        self.curatorisChainDate   = nil
        super.init()
        if self.isChainNavigationSourceSelected() {
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
        refreshPreviewIfNeeded()
        updateMenuBar()
    }

    private func updateMenuBar() {
        guard let statusItem = self.statusItem else { return }
        // Swapping the menu while it is open would drop the user out of browsing; rebuild on close instead
        if isMenuOpen {
            needsMenuRebuild = true
            return
        }
        let menu = NSMenu()
        menu.delegate = self

        // Preview with previous/next arrows for Curatoris or Bing
        if isChainNavigationSourceSelected() {
            let previewItem = NSMenuItem()
            let hostingView = NSHostingView(rootView: MenuPreviewView(
                model: preview,
                onPrevious: { [weak self] in self?.previous(nil) },
                onNext: { [weak self] in self?.next(nil) }
            ))
            hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
            previewItem.view = hostingView
            menu.addItem(previewItem)
            menu.addItem(.separator())
        }

        let setItem = NSMenuItem(title: "Set Wallpaper Now", action: #selector(setWallpaper(_:)), keyEquivalent: "w")
        setItem.target = self
        setItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        menu.addItem(setItem)

        let autoItem = NSMenuItem(
            title: autoRefreshEnabled ? "✓ Auto Refresh" : "Auto Refresh",
            action: #selector(toggleAutoRefresh),
            keyEquivalent: ""
        )
        autoItem.target = self
        menu.addItem(autoItem)

        if isChainNavigationSourceSelected() {
            menu.addItem(.separator())

            let galleryItem = NSMenuItem(title: "Gallery", action: #selector(openGallery), keyEquivalent: "")
            galleryItem.target = self
            galleryItem.image = NSImage(systemSymbolName: "photo.fill", accessibilityDescription: nil)
            menu.addItem(galleryItem)
        }

        menu.addItem(.separator())

        let lastItem = NSMenuItem(title: lastUpdateLabel, action: nil, keyEquivalent: "")
        lastItem.isEnabled = false
        menu.addItem(lastItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
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

    private func refreshPreviewIfNeeded() {
        guard isChainNavigationSourceSelected(), let date = curatorisChainDate else {
            previewKey = nil
            return
        }
        updatePreviewNavigation()

        let dateString = formattedChainDate()
        let key = "\(imageSourceSelection)|\(dateString ?? "")"
        guard key != previewKey else { return }
        previewKey = key

        let isBing = isBingSourceSelected()
        let bingIdx = currentBingIndex()
        let fallbackSubtitle = DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .none)
        preview.isLoading = true
        preview.imageURL = nil
        preview.title = "Loading…"
        preview.credit = fallbackSubtitle

        Task { @MainActor in
            let info: WallpaperPreview?
            if isBing {
                if let entry = await bingArchiveEntry(for: dateString) {
                    let (title, credit) = WallpaperPreview.splitCopyright(entry.copyright ?? entry.title)
                    info = WallpaperPreview(imageURL: URL(string: entry.thumb ?? entry.url), title: title, credit: credit)
                } else {
                    info = try? await BingSource().fetchPreview(idx: bingIdx)
                }
                // The archive may have just loaded, which changes how far back we can go
                updatePreviewNavigation()
            } else {
                info = try? await CuratorisSource().fetchPreview(for: dateString)
            }
            // A newer navigation may have started while this one was loading
            guard previewKey == key else { return }
            preview.isLoading = false
            preview.imageURL = info?.imageURL
            preview.title = info?.title ?? "No wallpaper for this day"
            preview.credit = info?.credit ?? fallbackSubtitle
        }
    }

    private var lastUpdateLabel: String {
        guard let last = lastUpdateTime else { return "Last Update: Never" }
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return "Last Update: \(f.string(from: last))"
    }

    private func updatePreviewNavigation() {
        guard let date = curatorisChainDate else {
            preview.canPrevious = false
            preview.canNext = false
            return
        }
        preview.canPrevious = canGoToPreviousDay()
        preview.canNext = Calendar.current.startOfDay(for: date) < today()
    }

    /// Bing's own archive only serves about a week; the self-hosted archive goes back much further.
    private static let directBingMaxIndex = 7

    private func canGoToPreviousDay() -> Bool {
        guard let date = curatorisChainDate else { return false }
        guard isBingSourceSelected() else { return date > Date(timeIntervalSince1970: 0) }
        if let oldest = bingArchive.first.flatMap({ Self.chainDateFormatter.date(from: $0.day) }) {
            return Calendar.current.startOfDay(for: date) > oldest
        }
        return currentBingIndex() < Self.directBingMaxIndex
    }

    /// Loads the self-hosted Bing archive at most once a day; an empty result means use direct Bing.
    private func loadBingArchiveIfNeeded() async {
        if let fetchedAt = bingArchiveFetchedAt, Calendar.current.isDateInToday(fetchedAt) { return }
        do {
            bingArchive = try await BingSource().fetchArchive().sorted { $0.day < $1.day }
            bingArchiveFetchedAt = Date()
        } catch {
            NSLog("Bing archive fetch failed, using direct Bing: \(error.localizedDescription)")
        }
    }

    private func bingArchiveEntry(for dateString: String?) async -> BingArchiveEntry? {
        guard let dateString else { return nil }
        await loadBingArchiveIfNeeded()
        return bingArchive.first { $0.day == dateString }
    }

    private func currentBingIndex() -> Int {
        guard isBingSourceSelected(), let date = curatorisChainDate else { return 0 }
        let daysDiff = Calendar.current.dateComponents([.day], from: date, to: today()).day ?? 0
        return max(0, daysDiff)
    }


    @objc private func toggleAutoRefresh()     { autoRefreshEnabled.toggle() }
    @objc private func quitApp()               { NSApp.terminate(nil) }
    @objc private func openGallery()           { GalleryWindowController.shared.showWindow() }
    @objc private func openSettings()          { SettingsWindowController.shared.showWindow() }
    @objc private func showAbout()             { AboutWindowController.shared.showWindow() }
    @objc private func checkForUpdatesTapped() { checkForUpdates(silentIfUpToDate: false) }

    @objc func setWallpaper(_ sender: AnyObject?) {
        if isChainNavigationSourceSelected() {
            resetCuratorisChainToToday()
            setWallpaperForChainDate()
        } else {
            setWallpaper()
        }
    }
    @objc func setWallpaper(overrideDate: Date? = nil) {
        guard !isInExcludedHours() else { return }
        Task { @MainActor in
            do {
                let currentSource = BuiltInSource.sanitized(UserDefaults.standard.string(forKey: "imageSource"))
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
                try wallpaperManager.setDesktopWallpaper(to: localPath)
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
    private func setWallpaperForChainDate() {
        guard curatorisChainDate != nil else { return }
        Task { @MainActor in
            do {
                let imageURL: URL?
                if isBingSourceSelected() {
                    if let entry = await bingArchiveEntry(for: formattedChainDate()) {
                        imageURL = URL(string: entry.url)
                    } else {
                        do {
                            imageURL = try await BingSource().fetchImageURL(idx: currentBingIndex())
                        } catch {
                            NSLog("Bing fetch error: \(error)")
                            imageURL = nil
                        }
                    }
                } else {
                    let source = CuratorisSource()
                    let dateString = formattedChainDate()
                    do {
                        imageURL = try await source.fetchImageURL(for: dateString)
                    } catch {
                        NSLog("Curatoris fetch error: \(error)")
                        imageURL = nil
                    }
                }
                guard let imageURL else {
                    NSLog("No image URL retrieved")
                    return
                }
                let localPath = try await wallpaperManager.downloadImage(from: imageURL)
                try wallpaperManager.setDesktopWallpaper(to: localPath)
                self.lastUpdateTime = Date()
                let source = isBingSourceSelected() ? BuiltInSource.bing.rawValue : BuiltInSource.curatoris.rawValue
                appendHistory(imageURL: imageURL.absoluteString, source: source)
                saveWallpaperToFolder(at: localPath)
                sendUpdateNotificationIfEnabled()
            } catch {
                NSLog("setWallpaperForChainDate error: \(error)")
            }
        }
    }

    @objc func previous(_ sender: AnyObject?) {
        guard isChainNavigationSourceSelected(), let chainDate = curatorisChainDate, canGoToPreviousDay() else { return }
        let prev = Calendar.current.date(byAdding: .day, value: -1, to: chainDate)!
        curatorisChainDate = prev
        autoRefreshEnabled = false
        setWallpaperForChainDate()
    }

    @objc func next(_ sender: AnyObject?) {
        guard isChainNavigationSourceSelected(), let chainDate = curatorisChainDate else { return }
        let today = self.today()
        let next = Calendar.current.date(byAdding: .day, value: 1, to: chainDate)!
        if Calendar.current.compare(next, to: today, toGranularity: .day) != .orderedDescending {
            curatorisChainDate = next
            setWallpaperForChainDate()
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
            struct Release: Decodable {
                let tag_name: String
                let html_url: String
            }

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

    private func isBingSourceSelected() -> Bool {
        imageSourceSelection == BuiltInSource.bing.rawValue
    }

    private func isChainNavigationSourceSelected() -> Bool {
        isCuratorisSourceSelected() || isBingSourceSelected()
    }

    private func today() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    private static let chainDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func formattedChainDate() -> String? {
        guard let date = curatorisChainDate else { return nil }
        return Self.chainDateFormatter.string(from: date)
    }

    private func resetCuratorisChainToToday() {
        curatorisChainDate = today()
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        if needsMenuRebuild {
            needsMenuRebuild = false
            updateMenuBar()
        }
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

/// Reads an API key from the environment, else from Info.plist (filled from Config.xcconfig at build time).
func bundledAPIKey(environment: String, infoKey: String) -> String? {
    if let env = ProcessInfo.processInfo.environment[environment], !env.isEmpty { return env }
    guard let plist = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String else { return nil }
    let key = plist.trimmingCharacters(in: .whitespacesAndNewlines)
    // An unset build setting leaves the value empty, or the literal "$(NAME)" if it was not expanded
    return key.isEmpty || key.hasPrefix("$(") ? nil : key
}

/// Shared access to the self-hosted Curatoris API.
enum CuratorisAPI {
    static let baseURL = "https://curatoris.mattikjellstadli.com/api/curatoris"

    static var apiKey: String? {
        bundledAPIKey(environment: "CURATORIS_API_KEY", infoKey: "CuratorisAPIKey")
    }

    /// An authenticated GET request for a path under the API base, or nil when no key is configured.
    static func request(path: String) -> URLRequest? {
        guard let apiKey, let url = URL(string: baseURL + path) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Curatoris/1.0", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        return request
    }
}

/// One day from the self-hosted Bing archive.
struct BingArchiveEntry: Decodable {
    let id: Int
    let title: String
    let url: String
    let thumb: String?
    let date: String?
    let copyright: String?

    /// The date as "yyyy-MM-dd" (empty when missing).
    var day: String { String((date ?? "").prefix(10)) }

    enum CodingKeys: String, CodingKey {
        case id, title, url, thumb, thumbUrl, date, copyright
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(String.self, forKey: .url)
        // The server entity names it thumbUrl; accept either
        thumb = try c.decodeIfPresent(String.self, forKey: .thumb) ?? c.decodeIfPresent(String.self, forKey: .thumbUrl)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        copyright = try c.decodeIfPresent(String.self, forKey: .copyright)
    }
}

struct BingSource: WallpaperSource {
    /// Every day stored by the self-hosted Bing archive.
    func fetchArchive() async throws -> [BingArchiveEntry] {
        guard let request = CuratorisAPI.request(path: "/bing/all") else {
            throw URLError(.userAuthenticationRequired)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([BingArchiveEntry].self, from: data)
    }

    func fetchImageURL(idx: Int = 0) async throws -> URL? {
        let safeIdx = max(0, idx)
        let apiURL = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=\(safeIdx)&n=1")!

        let (data, _) = try await URLSession.shared.data(from: apiURL)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let images = json?["images"] as? [[String: Any]],
            let urlBase = images.first?["urlbase"] as? String
        else {
            return nil
        }

        // Use UHD resolution for 4K
        return URL(string: "https://www.bing.com\(urlBase)_UHD.jpg")
    }

    func fetchImageURL() async throws -> URL? {
        return try await fetchImageURL(idx: 0)
    }

    func fetchPreview(idx: Int) async throws -> WallpaperPreview? {
        let safeIdx = max(0, idx)
        let apiURL = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=\(safeIdx)&n=1")!
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let image = (json?["images"] as? [[String: Any]])?.first,
            let urlBase = image["urlbase"] as? String
        else {
            return nil
        }
        let (title, credit) = WallpaperPreview.splitCopyright(image["copyright"] as? String ?? "Bing Image")
        return WallpaperPreview(
            imageURL: URL(string: "https://www.bing.com\(urlBase)_1280x720.jpg"),
            title: title,
            credit: credit
        )
    }
}

struct PicsumSource: WallpaperSource {
    func fetchImageURL() async throws -> URL? {
        URL(string: "https://picsum.photos/3840/2160")
    }
}

struct CuratorisSource: WallpaperSource {
    // Accepts an optional date string in yyyy-MM-dd format
    func fetchImageURL(for date: String? = nil) async throws -> URL? {
        guard let entry = try await fetchEntry(for: date) else { return nil }
        if let str = entry["url"] as? String {
            NSLog("CuratorisSource: Found URL: \(str)")
            return URL(string: str)
        }
        NSLog("CuratorisSource: No 'url' field in JSON or not a string")
        return nil
    }

    func fetchPreview(for date: String? = nil) async throws -> WallpaperPreview? {
        guard let entry = try await fetchEntry(for: date) else { return nil }
        guard let str = (entry["thumb"] as? String) ?? (entry["url"] as? String) else { return nil }
        return WallpaperPreview(
            imageURL: URL(string: str),
            title: entry["title"] as? String ?? "Curatoris",
            credit: entry["description"] as? String
        )
    }

    /// Fetches the raw wallpaper JSON object for a date (or today's when nil).
    private func fetchEntry(for date: String?) async throws -> [String: Any]? {
        guard let request = CuratorisAPI.request(path: date.map { "/date/\($0)" } ?? "") else {
            NSLog("CuratorisSource: Missing API key")
            return nil
        }

        NSLog("CuratorisSource: Request URL: \(request.url?.absoluteString ?? "nil")")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            NSLog("CuratorisSource: HTTP error \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            if let errorStr = String(data: data, encoding: .utf8) {
                NSLog("CuratorisSource: Error response: \(errorStr.prefix(500))")
            }
            return nil
        }

        // Log raw response
        if let rawStr = String(data: data, encoding: .utf8) {
            NSLog("CuratorisSource: Raw response: \(rawStr.prefix(500))")
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                NSLog("CuratorisSource: Parsed JSON: \(json)")
                return json
            } else if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                NSLog("CuratorisSource: Got array response, taking first element")
                return arr.first
            }
        } catch {
            NSLog("CuratorisSource: JSON parsing error: \(error)")
        }
        return nil
    }

    func fetchImageURL() async throws -> URL? {
        return try await fetchImageURL(for: nil)
    }
}

struct PexelsSource: WallpaperSource {
    static var apiKey: String? {
        bundledAPIKey(environment: "PEXELS_API_KEY", infoKey: "PexelsAPIKey")
    }

    func fetchImageURL() async throws -> URL? {
        guard let apiKey = Self.apiKey else { return nil }
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
            request.setValue(key, forHTTPHeaderField: "X-Api-Key")
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

// MARK: - Menu preview

struct WallpaperPreview {
    let imageURL: URL?
    let title: String
    let credit: String?

    /// Bing copyright strings look like "Tigresses, India (© Photographer/Agency)"; split off the credit.
    static func splitCopyright(_ copyright: String) -> (String, String?) {
        guard let range = copyright.range(of: " (©"), copyright.hasSuffix(")") else { return (copyright, nil) }
        let credit = copyright[range.upperBound...].dropLast().trimmingCharacters(in: .whitespaces)
        return (String(copyright[..<range.lowerBound]), "© " + credit)
    }
}

@MainActor
final class MenuPreviewModel: ObservableObject {
    @Published var imageURL: URL?
    @Published var title: String = ""
    @Published var credit: String?
    @Published var isLoading = false
    @Published var canPrevious = false
    @Published var canNext = false
}

struct MenuPreviewView: View {
    @ObservedObject var model: MenuPreviewModel
    let onPrevious: () -> Void
    let onNext: () -> Void

    private let imageSize = CGSize(width: 256, height: 144)
    private let arrowWidth: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                arrow("chevron.left", enabled: model.canPrevious, help: "Previous day", action: onPrevious)

                AsyncImage(url: model.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder { Image(systemName: "photo").foregroundStyle(.secondary) }
                    default:
                        placeholder {
                            if model.isLoading || model.imageURL != nil {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "photo").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(width: imageSize.width, height: imageSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                arrow("chevron.right", enabled: model.canNext, help: "Next day", action: onNext)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2, reservesSpace: true)
                Text(model.credit ?? " ")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: imageSize.width, alignment: .leading)
            .padding(.leading, arrowWidth + 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Color.secondary.opacity(0.12).overlay(content())
    }

    private func arrow(_ systemName: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .regular))
                .frame(width: arrowWidth, height: imageSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .primary : .tertiary)
        .disabled(!enabled)
        .help(help)
    }
}
