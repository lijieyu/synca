import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AppSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        settingsContent
            .syncaPreferences()
    }

    @ViewBuilder
    private var settingsContent: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            MacSheetHeader(title: "settings.title")
            Divider()
            settingsForm
            Divider()
            HStack {
                Spacer()
                Button("common.done") { dismiss() }
                    .buttonStyle(MacPrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }.padding(20)

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
    private var quotaColor: Color {
        #if os(iOS)
        .primary
        #else
        .accentColor
        #endif
    }
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
                            Capsule().fill(quotaColor)
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

#if os(iOS)
/// One native navigation stack owns all settings destinations on iPhone and iPad.
struct IOSSettingsView: View {
    private enum Destination: Hashable { case account, categories, ai, about }
    @ObservedObject private var settings = SettingsManager.shared
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var accessManager: AccessManager
    @State private var path: [Destination] = []
    @State private var feedbackPresented = false
    let onClose: () -> Void
    let onDeleteAccount: () async throws -> Void
    let onLogout: () -> Void

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: Destination.account) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 36)).foregroundStyle(.secondary).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("account.and_plan").font(.headline)
                                if let email = api.currentUserEmail {
                                    Text(verbatim: email).font(.subheadline).foregroundStyle(.secondary)
                                        .lineLimit(2).truncationMode(.middle)
                                }
                            }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("settings-account")
                }
                Section("settings.display") {
                    Picker("settings.appearance", selection: $settings.appAppearance) {
                        ForEach(AppAppearance.allCases) { item in Text(LocalizedStringKey(item.labelKey)).tag(item) }
                    }
                    Picker("settings.language", selection: $settings.appLanguage) {
                        ForEach(AppLanguage.allCases) { item in Text(LocalizedStringKey(item.labelKey)).tag(item) }
                    }
                }
                Section {
                    NavigationLink(value: Destination.categories) { Label("message_list.manage_categories", systemImage: "tag") }
                        .accessibilityIdentifier("settings-categories")
                    NavigationLink(value: Destination.ai) { Label("message_list.connect_ai", systemImage: "sparkles") }
                        .accessibilityIdentifier("settings-ai")
                }
                Section {
                    Button { feedbackPresented = true } label: {
                        HStack {
                            Label("message_list.feedback", systemImage: "bubble.left")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }.foregroundStyle(.primary)
                    }.accessibilityIdentifier("settings-feedback")
                    NavigationLink(value: Destination.about) { Label("message_list.about", systemImage: "info.circle") }
                        .accessibilityIdentifier("settings-about")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done", action: onClose).accessibilityIdentifier("settings-close")
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                destinationView(destination).navigationBarTitleDisplayMode(.inline)
            }
        }
        .tint(.primary)
        .sheet(isPresented: $feedbackPresented) { FeedbackComposerView().syncaPreferences() }
        .syncaPreferences()
    }

    @ViewBuilder private func destinationView(_ destination: Destination) -> some View {
        switch destination {
        case .account:
            AccountSheet(embedded: true, accountEmail: api.currentUserEmail,
                onDeleteAccount: onDeleteAccount, onLogout: onLogout)
                .navigationTitle("account.and_plan")
        case .categories:
            MessageCategoryManagerSheet(embedded: true).navigationTitle("message_list.manage_categories")
        case .ai:
            AIConnectionView(embedded: true).navigationTitle("message_list.connect_ai")
        case .about:
            AboutSyncaSheet(embedded: true).navigationTitle("message_list.about")
        }
    }
}
#endif
