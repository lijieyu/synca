import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AppSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        settingsContent
            .environment(\.locale, settings.locale)
            .preferredColorScheme(settings.appAppearance.colorScheme)
    }

    @ViewBuilder
    private var settingsContent: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            MacSheetHeader(title: "settings.title")
            Divider()
            settingsForm

        }
        .frame(width: min(420, (NSScreen.main?.visibleFrame.width ?? 520) - 80))
        .frame(maxHeight: (NSScreen.main?.visibleFrame.height ?? 860) - 100)
        .fixedSize(horizontal: false, vertical: true)
        #else
        NavigationStack {
            settingsForm
                .navigationTitle("settings.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.done") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var settingsForm: some View {
        Form {
            Section {
                Picker("settings.language", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(LocalizedStringKey(language.labelKey)).tag(language)
                    }
                }
                Picker("settings.appearance", selection: $settings.appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(LocalizedStringKey(appearance.labelKey)).tag(appearance)
                    }
                }
            } header: { Text("settings.display") }
            #if os(macOS)
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("settings.download_location")
                        Text(settings.macOSDefaultSavePath?.path ?? String(syncaLocalized: "settings.downloads"))
                            .font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("settings.change") { chooseDirectory() }
                }
                Toggle("settings.ask_download_location", isOn: $settings.asksForDownloadLocation)
            } header: { Text("settings.files") }
            #endif
        }
        .formStyle(.grouped)
    }

    #if os(macOS)
    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.macOSDefaultSavePath
        panel.message = String(syncaLocalized: "settings.download_location")
        panel.prompt = String(syncaLocalized: "settings.choose_directory")
        if panel.runModal() == .OK, let directory = panel.url {
            settings.setMacOSDefaultSavePath(directory)
        }
    }
    #endif
}

struct DailyQuotaView: View {
    let status: AccessStatus
    var body: some View {
        if !status.isUnlimited, let limit = status.todayLimit, limit > 0 {
            VStack(spacing: 7) {
                HStack {
                    Text("account.today_records")
                    Spacer()
                    Text("\(status.todayUsed) / \(limit)").monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    Capsule().fill(Color.secondary.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.syncaPurple)
                                .frame(width: geometry.size.width * Double(min(max(status.todayUsed, 0), limit)) / Double(limit))
                        }
                }
                    .frame(height: 4)
                    .accessibilityLabel(Text("account.today_records"))
                    .accessibilityValue(Text("\(status.todayUsed) / \(limit)"))
            }
        }
    }
}
