import SwiftUI
import SwiftData
import AppKit

@main
struct CuratorisApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows — menu bar only
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("App launched")

        // Prevent the app from appearing in the dock and from terminating when the last window closes
        NSApp.setActivationPolicy(.accessory)

        // Initialize menu bar controller and keep a strong reference
        menuBarController = MenuBarController()
        print("Menu bar controller initialized: \(String(describing: menuBarController))")

        // Prompt for osascript workaround if managed
        WallpaperManager.promptEnableOsascriptIfNeeded()
    }
}
