import SwiftUI
import Combine
import AppKit
import Security

// MARK: - Custom Source Model

struct CustomSource: Codable, Identifiable, Equatable {
    var id: String { url }
    var url: String
    var label: String

    var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return URL(string: url)?.host ?? url
    }
}

// MARK: - Keychain Helper

public enum KeychainHelper {
    private static let service = "com.curatoris.apikeys"

    static func save(key: String, for urlString: String) {
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: urlString
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        guard !key.isEmpty else { return }
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: urlString,
            kSecValueData: Data(key.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(for urlString: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: urlString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for urlString: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: urlString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Wallpaper History Entry

struct WallpaperHistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var url: String
    var setAt: Date
    var source: String

    init(url: String, setAt: Date, source: String) {
        self.id     = UUID()
        self.url    = url
        self.setAt  = setAt
        self.source = source
    }
}

// MARK: - Settings Model

@MainActor
final class SettingsModel: ObservableObject {
    @Published var autoRefreshEnabled: Bool       { didSet { UserDefaults.standard.set(autoRefreshEnabled,       forKey: "autoRefreshEnabled") } }
    @Published var useOsascriptForWallpaper: Bool { didSet { UserDefaults.standard.set(useOsascriptForWallpaper, forKey: "useOsascriptForWallpaper") } }
    @Published var refreshTime: String             { didSet { UserDefaults.standard.set(refreshTime,             forKey: "refreshTime") } }
    @Published var everyHourEnabled: Bool          { didSet { UserDefaults.standard.set(everyHourEnabled,        forKey: "everyHourEnabled") } }
    @Published var manualRefreshTimeEnabled: Bool  { didSet { UserDefaults.standard.set(manualRefreshTimeEnabled,forKey: "manualRefreshTimeEnabled") } }
    @Published var imageSource: String             { didSet { UserDefaults.standard.set(imageSource,             forKey: "imageSource") } }
    @Published var openAtLogin: Bool               { didSet { UserDefaults.standard.set(openAtLogin,             forKey: "openAtLogin") } }
    @Published var refreshOnWake: Bool             { didSet { UserDefaults.standard.set(refreshOnWake,           forKey: "refreshOnWake") } }
    @Published var notifyOnUpdate: Bool            { didSet { UserDefaults.standard.set(notifyOnUpdate,          forKey: "notifyOnUpdate") } }
    @Published var saveToFolder: Bool              { didSet { UserDefaults.standard.set(saveToFolder,            forKey: "saveToFolder") } }
    @Published var saveFolder: String              { didSet { UserDefaults.standard.set(saveFolder,              forKey: "saveFolder") } }
    @Published var excludeHoursEnabled: Bool       { didSet { UserDefaults.standard.set(excludeHoursEnabled,     forKey: "excludeHoursEnabled") } }
    @Published var excludeHourStart: Int           { didSet { UserDefaults.standard.set(excludeHourStart,        forKey: "excludeHourStart") } }
    @Published var excludeHourEnd: Int             { didSet { UserDefaults.standard.set(excludeHourEnd,          forKey: "excludeHourEnd") } }
    @Published var wallpaperFillMode: String       { didSet { UserDefaults.standard.set(wallpaperFillMode,       forKey: "wallpaperFillMode") } }
    @Published var historyLimit: Int               { didSet { UserDefaults.standard.set(historyLimit,            forKey: "historyLimit") } }
    @Published var lastUpdateTime: Date?           { didSet { if let d = lastUpdateTime { UserDefaults.standard.set(d, forKey: "lastUpdateTime") } else { UserDefaults.standard.removeObject(forKey: "lastUpdateTime") } } }

    @Published var wallpaperHistory: [WallpaperHistoryEntry] {
        didSet {
            if let encoded = try? JSONEncoder().encode(wallpaperHistory) {
                UserDefaults.standard.set(encoded, forKey: "wallpaperHistory")
            }
        }
    }

    @Published var customSources: [CustomSource] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customSources) {
                UserDefaults.standard.set(encoded, forKey: "customSourcesV2")
            }
        }
    }

    init() {
        self.autoRefreshEnabled       = UserDefaults.standard.bool(forKey: "autoRefreshEnabled")
        self.useOsascriptForWallpaper = UserDefaults.standard.bool(forKey: "useOsascriptForWallpaper")
        self.refreshTime              = UserDefaults.standard.string(forKey: "refreshTime") ?? "08:00"
        self.everyHourEnabled         = UserDefaults.standard.bool(forKey: "everyHourEnabled")
        self.manualRefreshTimeEnabled = UserDefaults.standard.bool(forKey: "manualRefreshTimeEnabled")
        self.imageSource              = UserDefaults.standard.string(forKey: "imageSource") ?? "Bing (Only 1080p)"
        self.openAtLogin              = UserDefaults.standard.bool(forKey: "openAtLogin")
        self.refreshOnWake            = UserDefaults.standard.bool(forKey: "refreshOnWake")
        self.notifyOnUpdate           = UserDefaults.standard.bool(forKey: "notifyOnUpdate")
        self.saveToFolder             = UserDefaults.standard.bool(forKey: "saveToFolder")
        self.saveFolder               = UserDefaults.standard.string(forKey: "saveFolder") ?? ""
        self.excludeHoursEnabled      = UserDefaults.standard.bool(forKey: "excludeHoursEnabled")
        self.excludeHourStart         = UserDefaults.standard.object(forKey: "excludeHourStart") as? Int ?? 22
        self.excludeHourEnd           = UserDefaults.standard.object(forKey: "excludeHourEnd")   as? Int ?? 7
        self.wallpaperFillMode        = UserDefaults.standard.string(forKey: "wallpaperFillMode") ?? "Fill"
        self.historyLimit             = UserDefaults.standard.object(forKey: "historyLimit") as? Int ?? 20
        self.lastUpdateTime           = UserDefaults.standard.object(forKey: "lastUpdateTime") as? Date

        if let data = UserDefaults.standard.data(forKey: "wallpaperHistory"),
           let decoded = try? JSONDecoder().decode([WallpaperHistoryEntry].self, from: data) {
            self.wallpaperHistory = decoded
        } else {
            self.wallpaperHistory = []
        }

        if let data = UserDefaults.standard.data(forKey: "customSourcesV2"),
           let decoded = try? JSONDecoder().decode([CustomSource].self, from: data) {
            self.customSources = decoded
        } else if let legacy = UserDefaults.standard.stringArray(forKey: "customSources") {
            self.customSources = legacy.map { CustomSource(url: $0, label: "") }
        } else {
            self.customSources = []
        }
    }
}

// MARK: - Sidebar Item

private enum SidebarItem: String, CaseIterable, Identifiable {
    case general  = "General"
    case images   = "Images"
    case history  = "History"
    case apis     = "APIs"
    case advanced = "Advanced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:  return "gearshape.fill"
        case .images:   return "photo.stack.fill"
        case .history:  return "clock.arrow.circlepath"
        case .apis:     return "link.badge.plus"
        case .advanced: return "wrench.and.screwdriver.fill"
        }
    }
}

// MARK: - API Format Popover

private struct APIFormatPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Expected API Response Format", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            Divider()
            Text("Your endpoint must return one of the following:")
                .font(.subheadline).foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Label("Option 1 — Direct redirect to an image", systemImage: "arrow.turn.down.right")
                    .font(.caption).foregroundColor(.secondary)
                Text("The URL itself resolves directly to an image file (PNG, JPEG, etc.).")
                    .font(.caption2).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("Option 2 — JSON with an image URL field", systemImage: "curlybraces")
                    .font(.caption).foregroundColor(.secondary)
                Text("Return a JSON object containing a `url` key:")
                    .font(.caption2).foregroundColor(.secondary)
                codeBlock("{\n  \"url\": \"https://example.com/photo.jpg\"\n}")
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("Option 3 — JSON array of image objects", systemImage: "list.bullet.rectangle")
                    .font(.caption).foregroundColor(.secondary)
                Text("Return a JSON array; the first item's `url` will be used:")
                    .font(.caption2).foregroundColor(.secondary)
                codeBlock("[\n  { \"url\": \"https://example.com/photo.jpg\" }\n]")
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label("API Key Authentication (optional)", systemImage: "key.fill")
                    .font(.caption).foregroundColor(.secondary)
                Text("If your endpoint requires a key, it will be sent as a Bearer token:")
                    .font(.caption2).foregroundColor(.secondary)
                codeBlock("Authorization: Bearer <your-api-key>")
            }
            Divider()
            Label("The endpoint must be publicly accessible and return a valid image URL.", systemImage: "exclamationmark.triangle")
                .font(.caption2).foregroundColor(.orange)
        }
        .padding(16)
        .frame(width: 360)
    }

    private func codeBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Source Row

private struct SourceRow: View {
    @Binding var source: CustomSource
    let isActive: Bool
    let onDelete: () -> Void

    @State private var apiKey: String = ""
    @State private var isExpanded: Bool = false
    @State private var isKeyVisible: Bool = false
    @State private var saveConfirmed: Bool = false
    @State private var hasKey: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    TextField("Label (optional)", text: $source.label)
                        .font(.body)
                        .textFieldStyle(.plain)
                    Text(source.url)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer()

                if hasKey {
                    Image(systemName: "key.fill")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                        .help("An API key is saved for this endpoint")
                }
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .help("Currently active source")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                        if isExpanded { apiKey = KeychainHelper.load(for: source.url) ?? "" }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "key")
                        .foregroundColor(isExpanded ? .secondary : .accentColor)
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? "Collapse" : "Manage API key")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 2)

            if isExpanded {
                Divider().padding(.top, 4)
                HStack(spacing: 8) {
                    Image(systemName: "key.horizontal")
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    Group {
                        if isKeyVisible {
                            TextField("Paste API key…", text: $apiKey)
                        } else {
                            SecureField("Paste API key…", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button { isKeyVisible.toggle() } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(isKeyVisible ? "Hide key" : "Show key")

                    Button {
                        KeychainHelper.save(key: apiKey, for: source.url)
                        hasKey = !apiKey.isEmpty
                        withAnimation { saveConfirmed = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { saveConfirmed = false }
                        }
                    } label: {
                        Label(saveConfirmed ? "Saved!" : "Save",
                              systemImage: saveConfirmed ? "checkmark.circle.fill" : "square.and.arrow.down")
                            .foregroundColor(saveConfirmed ? .green : .accentColor)
                    }
                    .buttonStyle(.borderless)
                    .disabled(apiKey.isEmpty)

                    if hasKey {
                        Button(role: .destructive) {
                            KeychainHelper.delete(for: source.url)
                            apiKey = ""
                            hasKey = false
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove saved API key")
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))

                Text("Stored securely in Keychain. Sent as a Bearer token with each request.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            }
        }
        .onAppear { hasKey = KeychainHelper.load(for: source.url) != nil }
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let entry: WallpaperHistoryEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .foregroundColor(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.source)
                    .font(.body)
            }
            Spacer()
            Text(DateFormatter.localizedString(from: entry.setAt, dateStyle: .short, timeStyle: .short))
                .font(.caption)
                .foregroundColor(.secondary)
            Button {
                if let url = URL(string: entry.url) { NSWorkspace.shared.open(url) }
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .help("Open image URL")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Settings View

public struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @State private var selection: SidebarItem = .general

    @State private var newURL: String = ""
    @State private var newLabel: String = ""
    @State private var newAPIKey: String = ""
    @State private var showKeyField: Bool = false
    @State private var isNewKeyVisible: Bool = false
    @State private var showingAPIInfo: Bool = false

    private let times       = (0..<24).map { String(format: "%02d:00", $0) }
    private let hours       = Array(0..<24)
    private let fillModes   = ["Fill", "Fit", "Stretch", "Center", "Tile"]
    private let historyLimits = [10, 20, 50, 100]
    private let builtInSources = ["Curatoris", "Bing (Only 1080p)", "Picsum", "Pexels"]

    private var hourlySupportedForCurrentSource: Bool {
        let src = model.imageSource
        return !(src == "Curatoris" || src == "Bing (Only 1080p)")
    }

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(160)
        } detail: {
            Group {
                switch selection {
                case .general:  generalPane
                case .images:   imagesPane
                case .history:  historyPane
                case .apis:     apisPane
                case .advanced: advancedPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 760, height: 520)
    }

    private var generalPane: some View {
        Form {
            Section {
                HStack {
                    Button { checkForUpdate() } label: {
                        Label("Check for Update", systemImage: "arrow.clockwise.circle")
                    }
                    Spacer()
                    Label("v\(currentVersionString)", systemImage: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            } header: {
                Label("About", systemImage: "app.badge.checkmark")
            }

            Section {
                Toggle(isOn: $model.autoRefreshEnabled) {
                    Label("Auto Refresh (Every Day)", systemImage: "arrow.clockwise.circle")
                }
                Toggle(isOn: $model.everyHourEnabled) {
                    Label("Refresh Every Hour", systemImage: "clock.arrow.circlepath")
                        .foregroundColor((!model.autoRefreshEnabled || !hourlySupportedForCurrentSource) ? .secondary : .primary)
                }
                .disabled(!model.autoRefreshEnabled || !hourlySupportedForCurrentSource)

                Toggle(isOn: $model.manualRefreshTimeEnabled) {
                    Label("Manual Refresh Time", systemImage: "clock.badge")
                        .foregroundColor((!model.autoRefreshEnabled || model.everyHourEnabled) ? .secondary : .primary)
                }
                .disabled(!model.autoRefreshEnabled || model.everyHourEnabled)

                HStack {
                    Label("Preferred Daily Time", systemImage: "clock")
                        .foregroundColor(canPickTime ? .primary : .secondary)
                    Spacer()
                    Picker("", selection: $model.refreshTime) {
                        ForEach(times, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .disabled(!canPickTime)
                }

                if !model.autoRefreshEnabled {
                    Text("Enable Auto Refresh to refresh once per day.")
                        .font(.caption).foregroundColor(.secondary)
                } else if !hourlySupportedForCurrentSource {
                    Text("Hourly refresh is not available for this source. Curatoris and Bing only change once per day.")
                        .font(.caption).foregroundColor(.secondary)
                } else if model.everyHourEnabled {
                    Text("Hourly override is active. The preferred daily time will be ignored.")
                        .font(.caption).foregroundColor(.secondary)
                } else if !model.manualRefreshTimeEnabled {
                    Text("Daily is the default. Enable Manual Refresh Time to pick a preferred hour.")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("If the Mac was asleep at the preferred time, Curatoris will catch up when it wakes.")
                        .font(.caption).foregroundColor(.secondary)
                }
            } header: {
                Label("Refresh Schedule", systemImage: "timer")
            }

            Section {
                Toggle(isOn: $model.refreshOnWake) {
                    Label("Refresh on Wake", systemImage: "sunrise.fill")
                }
                Toggle(isOn: $model.excludeHoursEnabled) {
                    Label("Exclude Hours", systemImage: "moon.zzz.fill")
                }
                if model.excludeHoursEnabled {
                    HStack {
                        Label("From", systemImage: "clock")
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $model.excludeHourStart) {
                            ForEach(hours, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        Text("to")
                            .foregroundColor(.secondary)
                        Picker("", selection: $model.excludeHourEnd) {
                            ForEach(hours, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    Text("Wallpaper will not be refreshed during these hours.")
                        .font(.caption).foregroundColor(.secondary)
                }
            } header: {
                Label("Behavior", systemImage: "wand.and.stars")
            } footer: {
                Text("Refresh on Wake triggers a new wallpaper whenever the Mac wakes from sleep.")
                    .font(.caption)
            }

            Section {
                Toggle(isOn: $model.notifyOnUpdate) {
                    Label("Notify on Wallpaper Change", systemImage: "bell.badge.fill")
                }
            } header: {
                Label("Notifications", systemImage: "bell.fill")
            } footer: {
                Text("Shows a macOS notification each time the wallpaper is updated.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var imagesPane: some View {
        Form {
            Section {
                HStack {
                    Label("Source", systemImage: "photo.on.rectangle")
                    Spacer()
                    Picker("", selection: $model.imageSource) {
                        Section("Built-in") {
                            ForEach(builtInSources, id: \.self) { Text($0).tag($0) }
                        }
                        if !model.customSources.isEmpty {
                            Section("Custom") {
                                ForEach(model.customSources) { src in
                                    Text(src.displayName).tag(src.url)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            } header: {
                Label("Wallpaper Source", systemImage: "photo.stack.fill")
            } footer: {
                Text("Built-in sources are maintained by Curatoris. Custom sources can be added in the APIs section.")
                    .font(.caption)
            }

            Section {
                HStack {
                    Label("Fill Mode", systemImage: "rectangle.arrowtriangle.2.outward")
                    Spacer()
                    Picker("", selection: $model.wallpaperFillMode) {
                        ForEach(fillModes, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            } header: {
                Label("Display", systemImage: "display")
            } footer: {
                Text("Controls how the wallpaper image is scaled to fit your screen.")
                    .font(.caption)
            }

            Section {
                Toggle(isOn: $model.saveToFolder) {
                    Label("Save Wallpapers to Folder", systemImage: "folder.badge.plus")
                }
                if model.saveToFolder {
                    HStack {
                        Label(
                            model.saveFolder.isEmpty ? "No folder selected" : model.saveFolder,
                            systemImage: "folder"
                        )
                        .foregroundColor(model.saveFolder.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseSaveFolder() }
                    }
                    if model.saveFolder.isEmpty {
                        Text("Choose a folder where each wallpaper will be saved automatically.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            } header: {
                Label("Storage", systemImage: "externaldrive.fill")
            } footer: {
                Text("Each new wallpaper is saved as a JPEG in the chosen folder.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var historyPane: some View {
        Form {
            Section {
                HStack {
                    Label("Keep Last", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Picker("", selection: $model.historyLimit) {
                        ForEach(historyLimits, id: \.self) { Text("\($0) wallpapers").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            } header: {
                Label("History Settings", systemImage: "gearshape")
            }

            if model.wallpaperHistory.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "clock.badge.xmark")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No wallpaper history yet.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            } else {
                Section {
                    ForEach(model.wallpaperHistory.reversed()) { entry in
                        HistoryRow(entry: entry)
                    }
                } header: {
                    HStack {
                        Text("Recent Wallpapers (\(model.wallpaperHistory.count))")
                        Spacer()
                        Button(role: .destructive) {
                            model.wallpaperHistory.removeAll()
                        } label: {
                            Label("Clear All", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var apisPane: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "flask.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This feature is in Beta")
                            .font(.headline)
                        Text("Custom API support is experimental and the expected response format may change in future versions.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: "tag")
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    TextField("Display name (optional)", text: $newLabel)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 8) {
                    Button { showingAPIInfo.toggle() } label: {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showingAPIInfo, arrowEdge: .leading) {
                        APIFormatPopover()
                    }
                    .help("Learn about the expected API response format")
                    TextField("https://example.com/image-endpoint", text: $newURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addCustomSource)
                }
                HStack(spacing: 8) {
                    Button {
                        withAnimation { showKeyField.toggle() }
                    } label: {
                        Label(showKeyField ? "Remove API Key" : "Add API Key",
                              systemImage: showKeyField ? "key.slash" : "key.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)

                    if showKeyField {
                        Group {
                            if isNewKeyVisible {
                                TextField("API key (optional)", text: $newAPIKey)
                            } else {
                                SecureField("API key (optional)", text: $newAPIKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                        Button { isNewKeyVisible.toggle() } label: {
                            Image(systemName: isNewKeyVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(isNewKeyVisible ? "Hide key" : "Show key")
                    }

                    Spacer()

                    Button(action: addCustomSource) {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(!isValidURL(newURL))
                }
            } header: {
                HStack {
                    Label("Custom API Sources", systemImage: "link.badge.plus")
                    Spacer()
                    Text("BETA")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: Capsule())
                }
            } footer: {
                Text("Enter a URL and an optional display name. The name appears in the source dropdown. Attach an API key if required — stored in Keychain, sent as a Bearer token. Tap ℹ︎ for the expected response format.")
                    .font(.caption)
            }

            if !model.customSources.isEmpty {
                Section {
                    ForEach($model.customSources) { $src in
                        SourceRow(
                            source: $src,
                            isActive: model.imageSource == src.url,
                            onDelete: { removeCustomSource(src) }
                        )
                    }
                } header: {
                    Text("Configured Endpoints (\(model.customSources.count))")
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "tray")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No custom sources added yet.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var advancedPane: some View {
        Form {
            Section {
                Toggle(isOn: $model.openAtLogin) {
                    Label("Open at Login", systemImage: "arrow.up.right.square")
                }
            } header: {
                Label("System", systemImage: "macwindow.on.rectangle")
            }

            Section {
                Toggle(isOn: $model.useOsascriptForWallpaper) {
                    Label("Use osascript to set wallpaper", systemImage: "terminal.fill")
                }
                .help("Enable this if your device requires using AppleScript (osascript) to set the wallpaper.")
            } header: {
                Label("Compatibility", systemImage: "exclamationmark.triangle.fill")
            } footer: {
                Text("Some managed Macs require AppleScript to set the wallpaper. If the default method fails, try enabling this.")
                    .font(.caption)
            }

            Section {
                HStack {
                    Label("Last Wallpaper Update", systemImage: "clock.badge.checkmark")
                    Spacer()
                    Text(model.lastUpdateTime.map {
                        DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)
                    } ?? "Never")
                    .foregroundColor(.secondary)
                    .font(.callout)
                }
                Button(role: .destructive) {
                    model.lastUpdateTime = nil
                } label: {
                    Label("Clear Last Update Record", systemImage: "trash.circle.fill")
                }
                .disabled(model.lastUpdateTime == nil)

                Button(role: .destructive) {
                    model.wallpaperHistory.removeAll()
                } label: {
                    Label("Clear Wallpaper History", systemImage: "clock.badge.xmark")
                }
                .disabled(model.wallpaperHistory.isEmpty)
            } header: {
                Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            } footer: {
                Text("Clearing history removes all locally stored wallpaper URLs. This does not delete any saved image files.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var canPickTime: Bool {
        model.autoRefreshEnabled && !model.everyHourEnabled && model.manualRefreshTimeEnabled
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles      = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK {
            model.saveFolder = panel.url?.path ?? ""
        }
    }

    private func addCustomSource() {
        let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidURL(url) else { return }
        guard !model.customSources.contains(where: { $0.url == url }) else {
            newURL = ""; newLabel = ""; newAPIKey = ""; return
        }
        let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        model.customSources.append(CustomSource(url: url, label: label))
        let key = newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { KeychainHelper.save(key: key, for: url) }
        newURL = ""; newLabel = ""; newAPIKey = ""
        showKeyField = false; isNewKeyVisible = false
    }

    private func removeCustomSource(_ src: CustomSource) {
        KeychainHelper.delete(for: src.url)
        model.customSources.removeAll { $0.url == src.url }
        if model.imageSource == src.url {
            model.imageSource = builtInSources.first ?? "Curatoris"
        }
    }

    private func isValidURL(_ str: String) -> Bool {
        guard let url = URL(string: str) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    private func checkForUpdate() {
        Task { @MainActor in
            let repoOwner = "mattkje"
            let repoName  = "Curatoris"
            guard let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }
            struct Release: Decodable { let tag_name: String; let html_url: String }
            func normalizeVersion(_ v: String) -> String {
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
                let latest  = normalizeVersion(release.tag_name)
                let current = normalizeVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
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

    private var currentVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
