import SwiftUI
import Foundation
import AppKit

struct Wallpaper: Identifiable, Hashable, Decodable {
    let id: Int
    let url: String
    let thumb: String
    let title: String
    let category: String?
    let description: String?
    let date: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, url, thumb, title, category, description, date, createdAt, updatedAt
    }

    init(id: Int, url: String, thumb: String, title: String, category: String? = nil, description: String? = nil, date: String? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.url = url
        self.thumb = thumb
        self.title = title
        self.category = category
        self.description = description
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct AlertMessage: Identifiable {
    let id = UUID()
    let message: String
}

struct GalleryView: View {
    @State private var searchText = ""
    @State private var selectedCategory: String = "All"
    @State private var wallpapers: [Wallpaper] = []
    @State private var categories: [String] = predefinedCategories
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var page: Int = 0
    @State private var hasMore: Bool = true
    @State private var currentSource: String = UserDefaults.standard.string(forKey: "imageSource") ?? "Curatoris"
    @State private var sourceCheckTimer: Timer? = nil
    private let pageSize = 50
    private let apiBase = "https://curatoris.mattikjellstadli.com/api/curatoris"
    private var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["CURATORIS_API_KEY"], !env.isEmpty { return env }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "CuratorisAPIKey") as? String, !plist.isEmpty { return plist }
        return nil
    }

    @State private var showSetWallpaperSheet = false
    @State private var selectedWallpaper: Wallpaper? = nil
    @State private var wallpaperActionMessage: AlertMessage? = nil

    private var isBingSourceSelected: Bool {
        currentSource == "Bing"
    }

    var filteredWallpapers: [Wallpaper] {
        let list = wallpapers.filter { isBingSourceSelected || selectedCategory == "All" || ($0.category ?? "").localizedCaseInsensitiveContains(selectedCategory) }
        if searchText.isEmpty { return list }
        return list.filter { $0.title.localizedCaseInsensitiveContains(searchText) || ($0.description ?? "").localizedCaseInsensitiveContains(searchText) }
    }

    public var body: some View {
        NavigationSplitView {
            // Sidebar: Search + Categories (only for Curatoris)
            VStack(alignment: .leading, spacing: 8) {
                SearchBar(text: $searchText)
                    .padding([.top, .horizontal])

                Divider().padding(.horizontal)

                if !isBingSourceSelected {
                    Text("Categories")
                        .font(.headline)
                        .padding(.horizontal)

                    List {
                        ForEach(categories, id: \.self) { cat in
                            Button(action: {
                                if selectedCategory != cat {
                                    selectedCategory = cat
                                    reloadWallpapers()
                                }
                            }) {
                                ZStack {
                                    if selectedCategory == cat {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.accentColor.opacity(0.15))
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.accentColor.opacity(0.001))
                                    }
                                    HStack {
                                        Text(cat.capitalized)
                                            .foregroundColor(selectedCategory == cat ? .accentColor : .primary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .buttonStyle(PlainButtonStyle())
                            .contentShape(Rectangle())
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    .listStyle(SidebarListStyle())
                }
            }
            .frame(minWidth: 220)
        } detail: {
            Group {
                if isLoading {
                    ProgressView().padding()
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if filteredWallpapers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No wallpapers found.")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                            ForEach(filteredWallpapers) { wallpaper in
                                WallpaperCard(
                                    wallpaper: wallpaper,
                                    isSelected: selectedWallpaper?.id == wallpaper.id,
                                    onTap: {
                                        selectedWallpaper = wallpaper
                                        showSetWallpaperSheet = true
                                    }
                                )
                            }
                        }
                        .padding()
                        if hasMore {
                            Button(action: { loadWallpapers(append: true) }) {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                    }
                                    Image(systemName: "arrow.down.circle")
                                    Text("Load More")
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding()
                            .disabled(isLoading)
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
        }
        .onAppear(perform: initialLoad)
        .onAppear {
            startSourceMonitoring()
        }
        .onDisappear {
            stopSourceMonitoring()
        }
        .sheet(isPresented: $showSetWallpaperSheet) {
            if let wallpaper = selectedWallpaper {
                SetWallpaperSheet(wallpaper: wallpaper, onSet: { url in
                    setWallpaper(from: url)
                }, onCancel: {
                    showSetWallpaperSheet = false
                })
            }
        }
        .alert(item: $wallpaperActionMessage) { msg in
            Alert(title: Text(msg.message))
        }
        .frame(minWidth: 700, minHeight: 420)
    }

    private func initialLoad() {
        let latestSource = UserDefaults.standard.string(forKey: "imageSource") ?? "Curatoris"
        if currentSource != latestSource {
            currentSource = latestSource
        }
        reloadWallpapers()
    }

    private func startSourceMonitoring() {
        sourceCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let latestSource = UserDefaults.standard.string(forKey: "imageSource") ?? "Curatoris"
            if currentSource != latestSource {
                NSLog("Gallery detected source change from \(currentSource) to \(latestSource)")
                currentSource = latestSource
                reloadWallpapers()
            }
        }
    }

    private func stopSourceMonitoring() {
        sourceCheckTimer?.invalidate()
        sourceCheckTimer = nil
    }

    private func reloadWallpapers() {
        page = 0
        hasMore = true
        wallpapers = []
        loadWallpapers(append: false)
    }

    private func loadWallpapers(append: Bool) {
        isLoading = true
        errorMessage = nil

        if isBingSourceSelected {
            // Try to load from API first, fallback to direct Bing API if not available
            loadBingWallpapersFromAPI(append: append)
        } else {
            loadCuratorisWallpapers(append: append)
        }
    }

    private func loadBingWallpapersFromAPI(append: Bool) {
        guard let apiKey = apiKey else {
            NSLog("GalleryView: Missing API key, falling back to direct Bing API")
            loadBingWallpapers(append: append)
            return
        }

        let urlString = "\(apiBase)/bing/all"
        guard let url = URL(string: urlString) else {
            NSLog("GalleryView: Invalid Bing API URL, falling back to direct Bing API")
            loadBingWallpapers(append: append)
            return
        }

        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Curatoris/1.0", forHTTPHeaderField: "User-Agent")
        req.httpShouldHandleCookies = false

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let http = response as? HTTPURLResponse {
                NSLog("GalleryView (Bing API): Response status: \(http.statusCode)")
                if http.statusCode != 200 {
                    NSLog("GalleryView (Bing API): Failed with status \(http.statusCode), falling back to direct Bing API")
                    DispatchQueue.main.async {
                        self.loadBingWallpapers(append: append)
                    }
                    return
                }
            }

            guard let data = data else {
                NSLog("GalleryView (Bing API): No data received, falling back to direct Bing API")
                DispatchQueue.main.async {
                    self.loadBingWallpapers(append: append)
                }
                return
            }

            do {
                // Try to decode as array of Bing wallpapers
                struct BingResponse: Decodable {
                    let id: Int
                    let title: String
                    let url: String
                    let thumb: String?
                    let date: String?
                }

                let bingWallpapers = try JSONDecoder().decode([BingResponse].self, from: data)
                NSLog("GalleryView (Bing API): Successfully loaded \(bingWallpapers.count) wallpapers from API")

                let wallpapers = bingWallpapers.map { bing in
                    Wallpaper(
                        id: bing.id,
                        url: bing.url,
                        thumb: bing.thumb ?? bing.url,
                        title: bing.title,
                        category: nil,
                        description: nil,
                        date: bing.date
                    )
                }

                DispatchQueue.main.async {
                    if append {
                        self.wallpapers += wallpapers
                    } else {
                        self.wallpapers = wallpapers
                    }
                    self.hasMore = false
                    self.isLoading = false
                }
            } catch {
                NSLog("GalleryView (Bing API): JSON decode failed: \(error), falling back to direct Bing API")
                DispatchQueue.main.async {
                    self.loadBingWallpapers(append: append)
                }
            }
        }.resume()
    }

    private func loadBingWallpapers(append: Bool) {
        Task {
            do {
                // Fetch multiple images with n=8
                guard let url = URL(string: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8") else {
                    DispatchQueue.main.async { isLoading = false; errorMessage = "Invalid Bing API URL" }
                    return
                }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    DispatchQueue.main.async { isLoading = false; errorMessage = "Failed to fetch from Bing" }
                    return
                }

                // Parse Bing response
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    DispatchQueue.main.async { isLoading = false; errorMessage = "Failed to parse Bing JSON" }
                    return
                }

                guard let images = json["images"] as? [[String: Any]] else {
                    DispatchQueue.main.async { isLoading = false; errorMessage = "Bing response missing images array" }
                    return
                }

                var wallpapers: [Wallpaper] = []
                for (index, img) in images.enumerated() {
                    guard let urlBase = img["urlbase"] as? String else {
                        NSLog("Skipping image at index \(index): missing urlbase")
                        continue
                    }

                    // Use UHD resolution for full-resolution (4K)
                    let fullURL = "https://www.bing.com\(urlBase)_UHD.jpg"
                    // For thumbnail, construct with smaller resolution
                    let thumbURL = "https://www.bing.com\(urlBase)_640x360.jpg"
                    let title = (img["copyright"] as? String) ?? "Bing Image"
                    let date = (img["startdate"] as? String) ?? ""

                    // Use startdate as unique id, fallback to index if not available
                    let uniqueId: Int
                    if let startdate = img["startdate"] as? String, let idFromDate = Int(startdate) {
                        uniqueId = idFromDate
                    } else {
                        uniqueId = index
                    }

                    let wallpaper = Wallpaper(
                        id: uniqueId,
                        url: fullURL,
                        thumb: thumbURL,
                        title: title,
                        category: nil,
                        description: img["copyrightlink"] as? String,
                        date: date
                    )
                    wallpapers.append(wallpaper)
                }

                DispatchQueue.main.async {
                    self.wallpapers = wallpapers
                    self.hasMore = false
                    self.isLoading = false
                }
            } catch {
                NSLog("loadBingWallpapers error: \(error)")
                DispatchQueue.main.async { isLoading = false; errorMessage = "Failed to load Bing wallpapers: \(error.localizedDescription)" }
            }
        }
    }

    private func loadCuratorisWallpapers(append: Bool) {
        guard let apiKey = apiKey else { errorMessage = "Missing API key"; isLoading = false; return }
        let urlString = "\(apiBase)/all"
        guard let url = URL(string: urlString) else { isLoading = false; return }
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Curatoris/1.0", forHTTPHeaderField: "User-Agent")
        req.httpShouldHandleCookies = false
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let http = response as? HTTPURLResponse {
                NSLog("GalleryView: Response status: \(http.statusCode)")
                NSLog("GalleryView: Request URL: \(req.url?.absoluteString ?? "nil")")
                NSLog("GalleryView: Request headers: \(req.allHTTPHeaderFields ?? [:])")
                if http.statusCode != 200, let data = data {
                    if let errorStr = String(data: data, encoding: .utf8) {
                        NSLog("GalleryView: Error response: \(errorStr.prefix(500))")
                    }
                }
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                DispatchQueue.main.async { isLoading = false; errorMessage = "Failed to fetch wallpapers: Unauthorized or server error" }
                return
            }
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    errorMessage = error.localizedDescription
                    NSLog("GalleryView: Network error: \(error.localizedDescription)")
                    return
                }
                guard let data = data else {
                    errorMessage = "No data from server"
                    NSLog("GalleryView: No data from server")
                    return
                }

                // Log raw data for debugging
                if let raw = String(data: data, encoding: .utf8) {
                    NSLog("GalleryView: Raw response data:\n\(raw.prefix(1000))")
                }

                do {
                    // Try to decode as array first (for backward compatibility)
                    var wallpaperArray: [Wallpaper] = []

                    do {
                        wallpaperArray = try JSONDecoder().decode([Wallpaper].self, from: data)
                    } catch {
                        // If array decoding fails, try single object
                        let singleWallpaper = try JSONDecoder().decode(Wallpaper.self, from: data)
                        wallpaperArray = [singleWallpaper]
                    }

                    let normalized = wallpaperArray.map { wp in
                        Wallpaper(
                            id: wp.id,
                            url: wp.url,
                            thumb: wp.thumb,
                            title: wp.title,
                            category: normalizedCategory(wp.category ?? ""),
                            description: wp.description,
                            date: wp.date,
                            createdAt: wp.createdAt,
                            updatedAt: wp.updatedAt
                        )
                    }
                    if append {
                        self.wallpapers += normalized
                    } else {
                        self.wallpapers = normalized
                    }
                    NSLog("GalleryView: Successfully loaded \(normalized.count) wallpapers")
                    hasMore = false
                } catch {
                    NSLog("GalleryView: JSON decode error: \(error)")
                    if let raw = String(data: data, encoding: .utf8) {
                        errorMessage = "Failed to decode wallpapers: \(error)\n\(raw.prefix(500))"
                    } else {
                        errorMessage = "Failed to decode wallpapers: \(error)"
                    }
                }
            }
        }.resume()
    }

    private func normalizedCategory(_ category: String) -> String {
        let match = predefinedCategories.first {
            $0.lowercased() == category.lowercased()
        }
        return match ?? "Other"
    }

    private func setWallpaper(from urlString: String) {
        guard let url = URL(string: urlString) else {
            wallpaperActionMessage = AlertMessage(message: "Invalid wallpaper URL.")
            return
        }
        Task {
            do {
                let manager = WallpaperManager()
                let path = try await manager.downloadImage(from: url)
                try manager.setDesktopWallpaper(to: path)
                DispatchQueue.main.async {
                    wallpaperActionMessage = AlertMessage(message: "Wallpaper set successfully!")
                    showSetWallpaperSheet = false
                }
            } catch {
                DispatchQueue.main.async {
                    wallpaperActionMessage = AlertMessage(message: "Failed to set wallpaper: \(error.localizedDescription)")
                }
            }
        }
    }
}

private let predefinedCategories: [String] = [
    "All",
    "Nature",
    "Space",
    "Abstract",
    "Minimal",
    "Architecture",
    "Cityscapes",
    "Technology",
    "Gaming",
    "Art",
    "Dark",
    "Gradients",
    "Other"
]

struct WallpaperCard: View {
    let wallpaper: Wallpaper
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(radius: isHovering ? 6 : 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            VStack(spacing: 0) {
                GeometryReader { geo in
                    AsyncImage(url: URL(string: wallpaper.thumb)) { phase in
                        switch phase {
                        case .empty:
                            ShimmerView()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            Image(systemName: "photo").foregroundColor(.secondary)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        @unknown default:
                            Color.gray
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(height: 100)
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.title)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let category = wallpaper.category {
                        Text(category)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if let date = wallpaper.date {
                        Text(date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 14)
            }
            .frame(width: 160, height: 140)
        }
        .frame(width: 160, height: 140)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(wallpaper.title))
    }
}

// Shimmer effect for loading placeholder
struct ShimmerView: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.1), Color.gray.opacity(0.3)]),
                               startPoint: .leading, endPoint: .trailing)
            )
            .mask(
                Rectangle()
                    .fill(Color.white)
                    .opacity(0.7)
                    .blur(radius: 8)
                    .offset(x: phase * 200 - 100)
            )
            .onAppear {
                withAnimation(Animation.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// Simple SearchBar for macOS
struct SearchBar: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField(string: "")
        searchField.delegate = context.coordinator
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        nsView.stringValue = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchBar
        init(_ parent: SearchBar) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSSearchField {
                parent.text = field.stringValue
            }
        }
    }
}

struct SetWallpaperSheet: View {
    let wallpaper: Wallpaper
    let onSet: (String) -> Void
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("Set Wallpaper")
                .font(.headline)
            AsyncImage(url: URL(string: wallpaper.url)) { phase in
                switch phase {
                case .empty:
                    Color.gray
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure:
                    Image(systemName: "photo").foregroundColor(.secondary)
                @unknown default:
                    Color.gray
                }
            }
            .frame(width: 320, height: 180)
            Text(wallpaper.title).font(.title3)
            HStack {
                Button("Set as Wallpaper") {
                    onSet(wallpaper.url)
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel") {
                    onCancel()
                }
            }
        }
        .padding(32)
        .frame(minWidth: 400)
    }
}
