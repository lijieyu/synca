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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(api)
                .environmentObject(syncManager)
                .environmentObject(accessManager)
                .environmentObject(purchaseManager)
            #if os(macOS)
                .background(MacWindowAccessor(isAuthenticated: api.isAuthenticated))
                .frame(minWidth: 400, idealWidth: 500, minHeight: 500, idealHeight: 700)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 500, height: 700)
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
