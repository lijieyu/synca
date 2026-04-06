import SwiftUI
import StoreKit

struct AccessCenterView: View {
    @EnvironmentObject private var accessManager: AccessManager
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            contentContainer
            #if os(iOS)
            .navigationTitle(String(localized: "access.center_title", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.ok") {
                        dismiss()
                    }
                }
            }
            .task {
                await purchaseManager.loadProducts()
                await accessManager.refresh()
            }
            .onDisappear {
                accessManager.clearUpgradeHighlight()
            }
        }
        .frame(minWidth: 360, idealWidth: 430)
        #if os(macOS)
        .frame(idealHeight: preferredMacHeight)
        #else
        .frame(minHeight: 420, idealHeight: 560)
        #endif
    }

    @ViewBuilder
    private func content(for status: AccessStatus) -> some View {
        if status.unlimitedSource == "lifetime" {
            lifetimeCurrentCard(status)
        } else if status.unlimitedSource == "subscription" {
            subscriptionCurrentCard(status)
        } else {
            currentFreeCard(status)
            unlockUnlimitedCard(status)
        }
    }

    @ViewBuilder
    private var contentContainer: some View {
        if let status = accessManager.status {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 16) {
                Text("access.center_title", bundle: .main)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                content(for: status)
            }
            .padding(20)
            #else
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content(for: status)
                }
                .padding(20)
            }
            #endif
        } else {
            ProgressView("message_list.loading")
                .frame(maxWidth: .infinity, minHeight: 260)
                .padding(20)
        }
    }

    private func currentFreeCard(_ status: AccessStatus) -> some View {
        AccessModuleCard(style: .neutral) {
            VStack(alignment: .leading, spacing: 14) {
                moduleHeader(
                    title: "access.current_plan_title",
                    badge: AccessStatusPill(status: status)
                )

                if status.isTrial {
                    Text(String(format: String(localized: "access.current_trial_summary", bundle: .main), status.daysLeft ?? 0))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text(String(format: String(localized: "access.current_free_summary", bundle: .main), status.todayUsed, status.todayLimit ?? 20))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                benefitRow(systemImage: "sparkles", text: "access.free_trial_rule")
                benefitRow(systemImage: "calendar.badge.clock", text: "access.free_daily_rule")
            }
        }
    }

    private func unlockUnlimitedCard(_ status: AccessStatus) -> some View {
        AccessModuleCard(style: .accent) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("access.unlock_title", bundle: .main)
                        .font(.headline)
                    Spacer()
                    restoreInlineButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    benefitRow(systemImage: "infinity", text: "access.unlock_benefit_unlimited")
                    benefitRow(systemImage: "ipad.and.iphone", text: "access.purchase_shared_account")
                    benefitRow(systemImage: "sparkles.rectangle.stack", text: "access.shared_future_feature")
                }

                VStack(spacing: 10) {
                    subscriptionPurchaseButton(.monthly)
                    subscriptionPurchaseButton(.yearly)
                    lifetimePurchaseButton()
                }

                statusMessageView
            }
        }
    }

    private func subscriptionCurrentCard(_ status: AccessStatus) -> some View {
        AccessModuleCard(style: .accent) {
            VStack(alignment: .leading, spacing: 16) {
                moduleHeader(
                    title: "access.current_plan_title",
                    badge: AccessStatusPill(status: status)
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(currentSubscriptionName(status))
                        .font(.title3.weight(.semibold))

                    if let purchaseDate = status.purchaseDate {
                        detailRow("access.purchase_date_label", value: formatDate(purchaseDate))
                    }
                    if let renewalDate = status.subscriptionExpiresAt {
                        detailRow("access.subscription_expires_label", value: formatDate(renewalDate))
                    }
                    benefitRow(systemImage: "checkmark.seal", text: "access.shared_base_feature")
                }

                if let switchProductID = alternateSubscriptionProduct(for: status) {
                    subscriptionSwitchButton(for: switchProductID)
                }

                lifetimeUpgradeSection(status)

                restoreFooterButton
                statusMessageView
            }
        }
    }

    private func lifetimeCurrentCard(_ status: AccessStatus) -> some View {
        AccessModuleCard(style: .accent) {
            VStack(alignment: .leading, spacing: 16) {
                moduleHeader(
                    title: "access.current_plan_title",
                    badge: AccessStatusPill(status: status)
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(currentLifetimeName)
                        .font(.title3.weight(.semibold))
                    if let purchaseDate = status.purchaseDate {
                        detailRow("access.purchase_date_label", value: formatDate(purchaseDate))
                    }
                    benefitRow(systemImage: "ipad.and.iphone", text: "access.purchase_shared_account")
                    benefitRow(systemImage: "checkmark.seal", text: "access.shared_base_feature")
                }

                restoreFooterButton
                statusMessageView
            }
        }
    }

    @ViewBuilder
    private func lifetimeUpgradeSection(_ status: AccessStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Text("access.lifetime_upgrade_title", bundle: .main)
                .font(.headline)

            if let offer = status.lifetimeUpgradeOffer, offer.isCodeAvailable {
                discountedLifetimeButton(offer)
            } else {
                standardLifetimeUpgradeButton
            }
        }
    }

    private func subscriptionPurchaseButton(_ productID: SyncaProductID) -> some View {
        let product = product(for: productID)
        let isEligibleForIntro = purchaseManager.isIntroOfferEligible(for: productID)
        let currentProductID = purchaseManager.purchasingProductID

        return Button {
            Task {
                _ = await purchaseManager.purchase(productID)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(product?.displayName ?? fallbackProductName(for: productID))
                        .font(planOptionTitleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 12)

                    if currentProductID == productID.rawValue {
                        ProgressView()
                            .controlSize(.small)
                    } else if let product {
                        if isEligibleForIntro {
                            Text(product.displayPrice)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .strikethrough()
                        } else {
                            Text(product.displayPrice)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text(subscriptionSubtitle(for: productID, product: product, isEligibleForIntro: isEligibleForIntro))
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    if isEligibleForIntro {
                        Text("access.intro_offer_badge", bundle: .main)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.18), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlanActionButtonStyle())
        .disabled(currentProductID != nil || product == nil || purchaseManager.isLoadingProducts)
    }

    private func lifetimePurchaseButton() -> some View {
        let currentProductID = purchaseManager.purchasingProductID

        return Button {
            Task {
                _ = await purchaseManager.purchase(.lifetime)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(currentLifetimeName)
                        .font(planOptionTitleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer()
                    if currentProductID == SyncaProductID.lifetime.rawValue {
                        ProgressView()
                            .controlSize(.small)
                    } else if let price = purchaseManager.lifetimeProduct?.displayPrice {
                        Text(price)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Text("access.option_lifetime_subtitle", bundle: .main)
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlanActionButtonStyle())
        .disabled(currentProductID != nil || purchaseManager.lifetimeProduct == nil || purchaseManager.isLoadingProducts)
    }

    private var standardLifetimeUpgradeButton: some View {
        Button {
            Task {
                _ = await purchaseManager.purchase(.lifetime)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(currentLifetimeName)
                        .font(planOptionTitleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer()
                    if purchaseManager.purchasingProductID == SyncaProductID.lifetime.rawValue {
                        ProgressView()
                            .controlSize(.small)
                    } else if let price = purchaseManager.lifetimeProduct?.displayPrice {
                        Text(price)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Text("access.option_lifetime_subtitle", bundle: .main)
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlanActionButtonStyle())
        .disabled(purchaseManager.purchasingProductID != nil || purchaseManager.lifetimeProduct == nil || purchaseManager.isLoadingProducts)
    }

    private func discountedLifetimeButton(_ offer: LifetimeUpgradeOffer) -> some View {
        Button {
            Task {
                _ = await purchaseManager.redeemLifetimeUpgradeOffer(offer)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(currentLifetimeName)
                        .font(planOptionTitleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer()
                    if purchaseManager.redeemingOfferKind == offer.kind {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        HStack(spacing: 6) {
                            if let original = purchaseManager.lifetimeProduct?.displayPrice {
                                Text(original)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .strikethrough()
                            }
                            Text(offer.discountedPriceLabel)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }

                Text("access.offer_code_hint", bundle: .main)
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlanActionButtonStyle())
        .disabled(purchaseManager.redeemingOfferKind != nil)
    }

    private var planOptionTitleFont: Font {
        .system(size: 17, weight: .semibold)
    }

    private func subscriptionSwitchButton(for productID: SyncaProductID) -> some View {
        Button {
            Task {
                _ = await purchaseManager.purchase(productID)
            }
        } label: {
            HStack {
                Text(productID == .yearly ? "access.switch_to_yearly" : "access.switch_to_monthly", bundle: .main)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if purchaseManager.purchasingProductID == productID.rawValue {
                    ProgressView()
                        .controlSize(.small)
                } else if let price = product(for: productID)?.displayPrice {
                    Text(price)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SecondaryPlanButtonStyle())
        .disabled(purchaseManager.purchasingProductID != nil || product(for: productID) == nil || purchaseManager.isLoadingProducts)
    }

    private var restoreInlineButton: some View {
        Button {
            Task { await purchaseManager.restorePurchases() }
        } label: {
            HStack(spacing: 6) {
                Text("access.restore_purchases", bundle: .main)
                    .font(.footnote.weight(.semibold))
                if purchaseManager.isRestoring {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .disabled(purchaseManager.isRestoring)
    }

    private var restoreFooterButton: some View {
        HStack {
            Spacer()
            restoreInlineButton
            Spacer()
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var statusMessageView: some View {
        if let message = purchaseManager.lastErrorMessage, !message.isEmpty {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func moduleHeader(title: LocalizedStringKey, badge: AccessStatusPill?) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.headline)
            Spacer()
            if let badge {
                badge
            }
        }
    }

    private func benefitRow(systemImage: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)
                .offset(y: benefitIconOffset(for: systemImage))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private func benefitIconOffset(for systemImage: String) -> CGFloat {
        #if os(iOS)
        switch systemImage {
        case "infinity":
            return 3.6
        case "ipad.and.iphone":
            return 2.2
        case "sparkles.rectangle.stack":
            return 1.4
        default:
            return 1
        }
        #else
        switch systemImage {
        case "infinity":
            return 1.4
        default:
            return 0
        }
        #endif
    }

    private func detailRow(_ key: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }

    private func product(for productID: SyncaProductID) -> Product? {
        switch productID {
        case .monthly:
            return purchaseManager.monthlyProduct
        case .yearly:
            return purchaseManager.yearlyProduct
        case .lifetime:
            return purchaseManager.lifetimeProduct
        }
    }

    private func alternateSubscriptionProduct(for status: AccessStatus) -> SyncaProductID? {
        switch status.storeProductId {
        case SyncaProductID.monthly.rawValue:
            return .yearly
        case SyncaProductID.yearly.rawValue:
            return .monthly
        default:
            return nil
        }
    }

    private func currentSubscriptionName(_ status: AccessStatus) -> String {
        switch status.storeProductId {
        case SyncaProductID.monthly.rawValue:
            return purchaseManager.monthlyProduct?.displayName ?? String(localized: "access.purchased_monthly", bundle: .main)
        case SyncaProductID.yearly.rawValue:
            return purchaseManager.yearlyProduct?.displayName ?? String(localized: "access.purchased_yearly", bundle: .main)
        default:
            return String(localized: "access.status_unlimited", bundle: .main)
        }
    }

    private var currentLifetimeName: String {
        purchaseManager.lifetimeProduct?.displayName ?? String(localized: "access.purchased_lifetime", bundle: .main)
    }

    private func fallbackProductName(for productID: SyncaProductID) -> String {
        switch productID {
        case .monthly:
            return String(localized: "access.option_monthly_title", bundle: .main)
        case .yearly:
            return String(localized: "access.option_yearly_title", bundle: .main)
        case .lifetime:
            return currentLifetimeName
        }
    }

    private func productSubtitle(for productID: SyncaProductID) -> String {
        switch productID {
        case .monthly:
            return String(localized: "access.option_monthly_subtitle", bundle: .main)
        case .yearly:
            return String(localized: "access.option_yearly_subtitle", bundle: .main)
        case .lifetime:
            return String(localized: "access.option_lifetime_subtitle", bundle: .main)
        }
    }

    private func subscriptionSubtitle(for productID: SyncaProductID, product: Product?, isEligibleForIntro: Bool) -> String {
        guard isEligibleForIntro, let price = product?.displayPrice else {
            return productSubtitle(for: productID)
        }

        switch productID {
        case .monthly:
            return String(format: String(localized: "access.option_monthly_intro_subtitle", bundle: .main), price)
        case .yearly:
            return String(format: String(localized: "access.option_yearly_intro_subtitle", bundle: .main), price)
        case .lifetime:
            return productSubtitle(for: productID)
        }
    }

    #if os(macOS)
    private var preferredMacHeight: CGFloat {
        guard let status = accessManager.status else { return 420 }
        if status.unlimitedSource == "lifetime" {
            return 320
        }
        if status.unlimitedSource == "subscription" {
            return 430
        }
        return 560
    }
    #endif

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

struct HeaderAccessBadge: View {
    let status: AccessStatus

    var body: some View {
        HStack(spacing: 3) {
            Text(labelText)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(status.isUnlimited ? Color.accentColor : .primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if !status.isUnlimited {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.secondary.opacity(0.10)))
        #if os(macOS)
        .help(helpText)
        #endif
    }

    private var labelText: String {
        if status.isUnlimited {
            return String(localized: "access.status_unlimited_inline", bundle: .main)
        }
        if status.isTrial {
            return String(format: String(localized: "access.status_trial_inline", bundle: .main), status.daysLeft ?? 0)
        }
        return String(format: String(localized: "access.status_free_inline", bundle: .main), status.todayUsed, status.todayLimit ?? 20)
    }

    private var helpText: String {
        if status.isUnlimited { return String(localized: "access.status_unlimited", bundle: .main) }
        if status.isTrial {
            return String(format: String(localized: "access.status_trial", bundle: .main), status.daysLeft ?? 0)
        }
        return String(format: String(localized: "access.status_free", bundle: .main), status.todayUsed, status.todayLimit ?? 20)
    }
}

struct AccessStatusPill: View {
    let status: AccessStatus
    var compact = false
    var emphasizeUpgrade = false
    var showUpgradeIndicator = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Text(labelText)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(status.isUnlimited ? Color.accentColor : .primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if showUpgradeIndicator {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: compact ? 12 : 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, compact ? 9 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(
            Capsule()
                .fill(status.isUnlimited ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
        )
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: showUpgradeIndicator && emphasizeUpgrade ? 1 : 0)
        )
        #if os(macOS)
        .help(helpText)
        #endif
    }

    private var labelText: String {
        if status.isUnlimited {
            return String(localized: "access.status_unlimited_inline", bundle: .main)
        }
        if status.isTrial {
            return String(format: String(localized: "access.status_trial_inline", bundle: .main), status.daysLeft ?? 0)
        }
        return String(format: String(localized: "access.status_free_inline", bundle: .main), status.todayUsed, status.todayLimit ?? 20)
    }

    private var borderColor: Color {
        status.isUnlimited ? Color.clear : Color.accentColor.opacity(emphasizeUpgrade ? 0.25 : 0)
    }

    private var helpText: String {
        if status.isUnlimited { return String(localized: "access.status_unlimited", bundle: .main) }
        if status.isTrial {
            return String(format: String(localized: "access.status_trial", bundle: .main), status.daysLeft ?? 0)
        }
        return String(format: String(localized: "access.status_free", bundle: .main), status.todayUsed, status.todayLimit ?? 20)
    }
}

private struct AccessModuleCard<Content: View>: View {
    enum Style {
        case neutral
        case accent
    }

    let style: Style
    private let content: Content

    init(style: Style, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var background: AnyShapeStyle {
        switch style {
        case .neutral:
            return AnyShapeStyle(Color.secondary.opacity(0.08))
        case .accent:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

private struct PlanActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .foregroundStyle(.white)
    }
}

private struct SecondaryPlanButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.16 : 0.10))
            )
            .foregroundStyle(Color.accentColor)
    }
}
