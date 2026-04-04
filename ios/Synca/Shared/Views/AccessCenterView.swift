import SwiftUI

struct AccessCenterView: View {
    @EnvironmentObject private var accessManager: AccessManager
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let status = accessManager.status {
                        statusCard(status)

                        if status.isUnlimited {
                            unlimitedBenefitsCard(status)
                        } else {
                            freeTierCard(status)
                            unlockBenefitsCard
                            purchaseOptionsCard
                        }
                    } else {
                        ProgressView("message_list.loading")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(20)
            }
            .navigationTitle(String(localized: "access.center_title", bundle: .main))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.ok") {
                        dismiss()
                    }
                }
            }
            .onDisappear {
                accessManager.clearUpgradeHighlight()
            }
            .task {
                await purchaseManager.loadProducts()
            }
        }
        .frame(minWidth: 360, idealWidth: 420, minHeight: 440, idealHeight: 560)
    }

    @ViewBuilder
    private func statusCard(_ status: AccessStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AccessStatusPill(status: status, emphasizeUpgrade: accessManager.shouldHighlightUpgrade)

            if status.isTrial {
                Text(String(format: String(localized: "access.trial_description", bundle: .main), status.daysLeft ?? 0))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if status.isFree {
                Text(String(format: String(localized: "access.free_description", bundle: .main), status.todayUsed, status.todayLimit ?? 20))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "access.unlimited_description", bundle: .main))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func freeTierCard(_ status: AccessStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("access.free_title", bundle: .main)
                .font(.headline)

            if status.isTrial {
                Label(String(format: String(localized: "access.trial_rule", bundle: .main), status.daysLeft ?? 0), systemImage: "sparkles")
            } else {
                Label(String(format: String(localized: "access.free_rule", bundle: .main), status.todayLimit ?? 20), systemImage: "calendar")
                Label(String(format: String(localized: "access.free_usage", bundle: .main), status.todayUsed, status.todayLimit ?? 20), systemImage: "chart.bar")
            }

            Label("access.free_keep_access", systemImage: "tray.full")
            Label("access.free_reset_hint", systemImage: "arrow.clockwise")
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var unlockBenefitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("access.unlock_title", bundle: .main)
                .font(.headline)

            Label("access.unlock_benefit_unlimited", systemImage: "infinity")
            Label("access.unlock_benefit_cross_device", systemImage: "ipad.and.iphone")
            Label("access.unlock_benefit_capture_anytime", systemImage: "bolt")
            Label("access.purchase_shared_account", systemImage: "person.crop.circle.badge.checkmark")
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var purchaseOptionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("access.purchase_options_title", bundle: .main)
                .font(.headline)
            Text("access.purchase_shared_hint", bundle: .main)
                .font(.footnote)
                .foregroundStyle(.secondary)

            purchaseOptionRow(
                title: "access.option_monthly_title",
                subtitle: "access.option_monthly_subtitle",
                priceText: purchaseManager.monthlyProduct?.displayPrice,
                isLoading: purchaseManager.purchasingProductID == SyncaProductID.monthly.rawValue
            ) {
                Task {
                    _ = await purchaseManager.purchase(.monthly)
                }
            }
            purchaseOptionRow(
                title: "access.option_yearly_title",
                subtitle: "access.option_yearly_subtitle",
                priceText: purchaseManager.yearlyProduct?.displayPrice,
                isLoading: purchaseManager.purchasingProductID == SyncaProductID.yearly.rawValue
            ) {
                Task {
                    _ = await purchaseManager.purchase(.yearly)
                }
            }
            purchaseOptionRow(
                title: "access.option_lifetime_title",
                subtitle: "access.option_lifetime_subtitle",
                priceText: purchaseManager.lifetimeProduct?.displayPrice,
                isLoading: purchaseManager.purchasingProductID == SyncaProductID.lifetime.rawValue
            ) {
                Task {
                    _ = await purchaseManager.purchase(.lifetime)
                }
            }

            Divider()

            if let errorMessage = purchaseManager.lastErrorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await purchaseManager.restorePurchases() }
            } label: {
                HStack(spacing: 8) {
                    if purchaseManager.isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("access.restore_purchases", bundle: .main)
                        .font(.footnote.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .disabled(purchaseManager.isRestoring)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func purchaseOptionRow(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        priceText: String?,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if let priceText {
                    Text(String(format: String(localized: "access.buy_for_price", bundle: .main), priceText))
                        .font(.footnote.weight(.semibold))
                } else if purchaseManager.isLoadingProducts {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("access.purchase_unavailable_short", bundle: .main)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading || purchaseManager.isLoadingProducts || priceText == nil)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func purchaseSourceLabel(_ status: AccessStatus) -> some View {
        if status.unlimitedSource == "lifetime" {
            Label("access.purchased_lifetime", systemImage: "seal.fill")
        } else if status.unlimitedSource == "subscription" {
            if status.storeProductId == SyncaProductID.monthly.rawValue {
                Label("access.purchased_monthly", systemImage: "calendar.badge.clock")
            } else {
                Label("access.purchased_yearly", systemImage: "calendar.badge.clock")
            }
        }
    }

    @ViewBuilder
    private func unlimitedBenefitsCard(_ status: AccessStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("access.unlimited_title", bundle: .main)
                .font(.headline)

            Label("access.unlock_benefit_unlimited", systemImage: "infinity")
            Label("access.unlock_benefit_cross_device", systemImage: "ipad.and.iphone")
            Label("access.unlock_benefit_capture_anytime", systemImage: "bolt")
            Label("access.purchase_shared_account", systemImage: "person.crop.circle.badge.checkmark")
            purchaseSourceLabel(status)

            if let purchaseDate = status.purchaseDate {
                Label(String(format: String(localized: "access.purchase_date", bundle: .main), formatDate(purchaseDate)), systemImage: "calendar")
            }

            if let subscriptionExpiresAt = status.subscriptionExpiresAt {
                Label(String(format: String(localized: "access.subscription_expires", bundle: .main), formatDate(subscriptionExpiresAt)), systemImage: "clock")
            }

            Divider()

            Button {
                Task { await purchaseManager.restorePurchases() }
            } label: {
                HStack(spacing: 8) {
                    if purchaseManager.isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("access.restore_purchases", bundle: .main)
                        .font(.footnote.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .disabled(purchaseManager.isRestoring)
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.14), Color.yellow.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: isoString) ?? fallbackFormatter.date(from: isoString)
        guard let date else { return isoString }

        let output = DateFormatter()
        output.locale = .current
        output.setLocalizedDateFormatFromTemplate("yMMMd")
        return output.string(from: date)
    }
}

struct AccessStatusPill: View {
    let status: AccessStatus
    var emphasizeUpgrade = false
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            if !compact {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(labelText)
                .font(.system(size: compact ? 10.5 : 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background {
            Capsule()
                .fill(backgroundFillStyle)
        }
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: emphasizeUpgrade ? 1.2 : 0)
        )
        #if os(macOS)
        .help(fullLabelText)
        #endif
    }

    private var labelText: String {
        if compact {
            if status.isUnlimited {
                return String(localized: "access.status_unlimited_compact", bundle: .main)
            }
            if status.isTrial {
                return String(format: String(localized: "access.status_trial_compact", bundle: .main), status.daysLeft ?? 0)
            }
            return String(format: String(localized: "access.status_free_compact", bundle: .main), status.todayUsed, status.todayLimit ?? 20)
        }
        return fullLabelText
    }

    private var fullLabelText: String {
        if status.isUnlimited {
            return String(localized: "access.status_unlimited", bundle: .main)
        }
        if status.isTrial {
            return String(format: String(localized: "access.status_trial", bundle: .main), status.daysLeft ?? 0)
        }
        return String(format: String(localized: "access.status_free", bundle: .main), status.todayUsed, status.todayLimit ?? 20)
    }

    private var iconName: String {
        if status.isUnlimited { return "crown.fill" }
        if status.isTrial { return "sparkles" }
        return "bolt.badge.clock"
    }

    private var foregroundColor: Color {
        if status.isUnlimited { return .orange }
        return .accentColor
    }

    private var backgroundFillStyle: AnyShapeStyle {
        if status.isUnlimited {
            return AnyShapeStyle(LinearGradient(
                colors: [Color.orange.opacity(0.20), Color.yellow.opacity(0.12)],
                startPoint: .leading,
                endPoint: .trailing
            ))
        } else {
            return AnyShapeStyle(Color.accentColor.opacity(emphasizeUpgrade ? 0.18 : 0.12))
        }
    }

    private var borderColor: Color {
        status.isUnlimited ? Color.orange.opacity(0.38) : Color.accentColor.opacity(0.32)
    }
}
