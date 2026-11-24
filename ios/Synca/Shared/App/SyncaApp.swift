import SwiftUI

@main
struct SyncaApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #endif

    @StateObject private var api = APIClient.shared
    @StateObject private var syncManager = SyncManager.shared
    @StateObject private var accessManager = AccessManager.shared
    @StateObject private var purchaseManager = PurchaseManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(api)
                .environmentObject(syncManager)
                .environmentObject(accessManager)
                .environmentObject(purchaseManager)
                .environment(\.locale, settings.locale)
                .preferredColorScheme(settings.appAppearance.colorScheme)
            #if os(macOS)
                .background(MacWindowAccessor(isAuthenticated: api.isAuthenticated))
                .frame(minWidth: 640, idealWidth: 1000, minHeight: 500, idealHeight: 700)
            #endif
        }
        #if os(iOS)
        .onChange(of: scenePhase) { phase in
            if phase == .active { syncManager.startPolling() }
            else if phase == .background { syncManager.stopPolling() }
        }
        .onChange(of: api.isAuthenticated) { authenticated in
            if authenticated && scenePhase == .active { syncManager.startPolling() }
            else if !authenticated { syncManager.stopPolling() }
        }
        #endif
        #if os(macOS)
        .defaultSize(width: 1000, height: 740)
        .commands {
            // Remove "New Window" / "New Tab" menu items
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject var api: APIClient

    var body: some View {
        Group {
            if api.isAuthenticated {
                MessageListView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: api.isAuthenticated)

    }
}
