import SwiftUI
import Combine
import AppKit
import Security

// MARK: - Custom Source Model

struct CustomSource: Codable, Identifiable, Equatable {
    var id: String { url }
    var url: String
    var label: String

    /// Display name: label if non-empty, otherwise the bare hostname.
    var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return URL(string: url)?.host ?? url
    }
}

// MARK: - Keychain Helper

public enum KeychainHelper {
    private static let service = "com.dailywall.apikeys"

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

// MARK: - Settings Model

@MainActor
final class SettingsModel: ObservableObject {
    @Published var autoRefreshEnabled: Bool { didSet { UserDefaults.standard.set(autoRefreshEnabled, forKey: "autoRefreshEnabled") } }
    @Published var refreshTime: String      { didSet { UserDefaults.standard.set(refreshTime, forKey: "refreshTime") } }
    @Published var everyHourEnabled: Bool   { didSet { UserDefaults.standard.set(everyHourEnabled, forKey: "everyHourEnabled") } }
    @Published var imageSource: String      { didSet { UserDefaults.standard.set(imageSource, forKey: "imageSource") } }
    @Published var openAtLogin: Bool        { didSet { UserDefaults.standard.set(openAtLogin, forKey: "openAtLogin") } }
    @Published var lastUpdateTime: Date?    { didSet { if let d = lastUpdateTime { UserDefaults.standard.set(d, forKey: "lastUpdateTime") } else { UserDefaults.standard.removeObject(forKey: "lastUpdateTime") } } }

    @Published var customSources: [CustomSource] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customSources) {
                UserDefaults.standard.set(encoded, forKey: "customSourcesV2")
            }
        }
    }

    init() {
        self.autoRefreshEnabled = UserDefaults.standard.bool(forKey: "autoRefreshEnabled")
        self.refreshTime        = UserDefaults.standard.string(forKey: "refreshTime") ?? "08:00"
        self.everyHourEnabled   = UserDefaults.standard.bool(forKey: "everyHourEnabled")
        self.imageSource        = UserDefaults.standard.string(forKey: "imageSource") ?? "Bing (Only 1080p)"
        self.openAtLogin        = UserDefaults.standard.bool(forKey: "openAtLogin")
        self.lastUpdateTime     = UserDefaults.standard.object(forKey: "lastUpdateTime") as? Date

        // Load V2 (CustomSource array), or migrate from legacy plain-string array
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
            // --- Main row ---
            HStack {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    // Editable label (shown as placeholder text when empty)
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
                        if isExpanded {
                            apiKey = KeychainHelper.load(for: source.url) ?? ""
                        }
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

            // --- Expandable key editor ---
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

// MARK: - Settings View

public struct SettingsView: View {
    @StateObject private var model = SettingsModel()

    // New-source form state
    @State private var newURL: String = ""
    @State private var newLabel: String = ""
    @State private var newAPIKey: String = ""
    @State private var showKeyField: Bool = false
    @State private var isNewKeyVisible: Bool = false
    @State private var showingAPIInfo: Bool = false

    private let times = (0..<24).map { String(format: "%02d:00", $0) }
    private let builtInSources = ["DailyWall","Bing (Only 1080p)", "Picsum", "Pexels"]

    public init() {}

    public var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape.2.fill") }
                .tag(0)
            apiTab
                .tabItem { Label("APIs", systemImage: "link.badge.plus") }
                .tag(1)
            advancedTab
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver.fill") }
                .tag(2)
        }
        .padding(.top, 4)
    }

    private var generalTab: some View {
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
                    Label("Auto Refresh", systemImage: "arrow.clockwise.circle")
                }
                Toggle(isOn: $model.everyHourEnabled) {
                    Label("Refresh Every Hour", systemImage: "clock.arrow.circlepath")
                }
                .disabled(!model.autoRefreshEnabled)

                HStack {
                    Label("Daily Refresh Time", systemImage: "clock")
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
                    Text("Enable Auto Refresh to configure a schedule.")
                        .font(.caption).foregroundColor(.secondary)
                } else if model.everyHourEnabled {
                    Text("Hourly refresh is active. The daily time picker is disabled.")
                        .font(.caption).foregroundColor(.secondary)
                }
            } header: {
                Label("Refresh Schedule", systemImage: "timer")
            }

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
                Label("Images", systemImage: "photo.stack")
            }
        }
        .formStyle(.grouped)
    }

    private var canPickTime: Bool { model.autoRefreshEnabled && !model.everyHourEnabled }

    private var apiTab: some View {
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
    
    private var advancedTab: some View {
        Form {
            Section {
                Toggle(isOn: $model.openAtLogin) {
                    Label("Open at Login", systemImage: "arrow.up.right.square")
                }
            } header: {
                Label("System", systemImage: "macwindow.on.rectangle")
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
            } header: {
                Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            } footer: {
                Text("Clearing this record will cause the next refresh to treat the wallpaper as never having been set.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func addCustomSource() {
        let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidURL(url) else { return }
        guard !model.customSources.contains(where: { $0.url == url }) else {
            newURL = ""; newLabel = ""; newAPIKey = ""
            return
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
            model.imageSource = builtInSources.first ?? "DailyWall"
        }
    }

    private func isValidURL(_ str: String) -> Bool {
        guard let url = URL(string: str) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    private func checkForUpdate() {
        Task { @MainActor in
            let repoOwner = "mattkje"
            let repoName  = "DailyWall"
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "\(version)"
    }
}
