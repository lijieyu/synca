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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(api)
                .environmentObject(syncManager)
            #if os(macOS)
                .frame(minWidth: 400, idealWidth: 480, minHeight: 500, idealHeight: 700)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 480, height: 700)
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
