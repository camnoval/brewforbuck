//
//  PaywallView.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 9/9/26.
//

import SwiftUI
import CoreContracts
import CoreServices

/// The supporter sheet.
///
/// Holds a `PaywallState` and hands every event to `PaywallFlow.next`. There is no `if` in here
/// that decides anything: the view renders whatever state comes back and reports what the person
/// did. That is why all six purchase outcomes are testable without a simulator.
///
/// Prices are always the store's own strings, never formatted here (§10).
struct PaywallView: View {
    @ObservedObject var store: SupporterStore
    @Environment(\.dismiss) private var dismiss

    @State private var state: PaywallState = PaywallFlow.initial

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.loose) {
                    header
                    content
                }
                .padding(Theme.Space.base)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.glass)
                }
            }
        }
        .task { await start() }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            Wordmark(size: 34)
            Text("ABV is free and stays free. If it saved you a bad order, you can buy me a drink.")
                .font(Theme.callout)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {

        case .loading:
            HStack(spacing: Theme.Space.tight) {
                ProgressView()
                Text("Checking prices")
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Theme.Space.wide)

        case .unavailable:
            // No prices in hand, so none are shown. A guess here would be a fabricated price.
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                Text("Could not reach the App Store just now.")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.ink)
                Button("Try again") { Task { await retry() } }
                    .buttonStyle(PourButtonStyle())
                restoreButton(isBusy: false)
            }

        case .ready(let tiers, let notice):
            tierList(tiers, notice: notice, busyWith: nil)

        case .purchasing(let tiers, let chosen):
            tierList(tiers, notice: nil, busyWith: chosen)

        case .restoring(let tiers):
            tierList(tiers, notice: nil, busyWith: nil, isRestoring: true)

        case .pending:
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                Text("Waiting on approval")
                    .font(Theme.title)
                    .foregroundStyle(Theme.ink)
                // Nothing is owed yet, so this deliberately does not thank them.
                Text("Your purchase needs approval before it goes through. Nothing has been charged yet.")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Done") { dismiss() }
                    .buttonStyle(PourButtonStyle())
            }

        case .thanks(let productIdentifier):
            thanks(productIdentifier)
        }
    }

    @ViewBuilder
    private func tierList(
        _ tiers: [SupporterTier],
        notice: PaywallNotice?,
        busyWith chosen: SupporterTier?,
        isRestoring: Bool = false
    ) -> some View {
        VStack(spacing: Theme.Space.snug) {
            ForEach(tiers) { tier in
                Button {
                    Task { await buy(tier) }
                } label: {
                    TierRow(tier: tier, isBusy: chosen == tier)
                }
                .buttonStyle(.plain)
                .disabled(chosen != nil || isRestoring)
            }

            if let notice {
                Text(message(for: notice))
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("One time. No subscription.")
                .font(Theme.micro)
                .foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            restoreButton(isBusy: isRestoring)
        }
    }

    @ViewBuilder
    private func thanks(_ productIdentifier: String?) -> some View {
        let kind = productIdentifier.map(SupporterTierKind.resolve(productIdentifier:))
            ?? store.tierKind
            ?? .unspecified

        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            HStack(spacing: Theme.Space.tight) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.glass)
                Text(kind.thanksHeadline)
                    .font(Theme.title)
                    .foregroundStyle(Theme.ink)
            }
            Text("That is it, forever. ABV will not ask again.")
                .font(Theme.callout)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { dismiss() }
                .buttonStyle(PourButtonStyle())
        }
    }

    private func restoreButton(isBusy: Bool) -> some View {
        Button {
            Task { await restore() }
        } label: {
            HStack(spacing: Theme.Space.tight) {
                if isBusy { ProgressView() }
                Text(isBusy ? "Checking" : "Restore purchase")
            }
            .font(Theme.label)
            .foregroundStyle(Theme.inkMuted)
        }
        .disabled(isBusy)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, Theme.Space.hair)
    }

    /// Copy for each notice. Plain muted text rather than `Notice`, which is amber and reserved for
    /// estimate warnings.
    private func message(for notice: PaywallNotice) -> String {
        switch notice {
        case .purchaseDidNotGoThrough:
            "That did not go through. Nothing was charged. You can try again."
        case .nothingToRestore:
            "Nothing to restore on this Apple Account."
        case .restoreDidNotGoThrough:
            "Could not check for a previous purchase just now."
        }
    }

    // MARK: - Events
    //
    // Each of these does the async work and reports the result. The transition itself is always
    // `PaywallFlow.next`, never an assignment decided here.

    private func send(_ event: PaywallEvent) {
        state = PaywallFlow.next(from: state, on: event)
    }

    private func start() async {
        // Someone who already supported the app never sees the tier list (§ one-time rule).
        await store.refresh()
        if case .supporter(let identifier) = store.status {
            state = .thanks(productIdentifier: identifier)
            return
        }
        await loadTiers()
    }

    private func loadTiers() async {
        do {
            send(.tiersLoaded(try await store.purchases.supporterTiers()))
        } catch {
            send(.tiersFailed)
        }
    }

    private func retry() async {
        send(.retryRequested)
        await loadTiers()
    }

    private func buy(_ tier: SupporterTier) async {
        send(.tierChosen(tier))
        do {
            let outcome = try await store.purchases.purchase(tier)
            await store.refresh()
            send(.purchaseFinished(outcome))
        } catch {
            send(.purchaseFailed)
        }
    }

    private func restore() async {
        send(.restoreRequested)
        do {
            let outcome = try await store.purchases.restorePurchases()
            await store.refresh()
            send(.restoreFinished(outcome))
        } catch {
            send(.restoreFailed)
        }
    }
}

// MARK: - One tier

/// A tier row: name on the left from the store, price on the right from the store.
private struct TierRow: View {
    let tier: SupporterTier
    let isBusy: Bool

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            Text(tier.displayName)
                .font(Theme.action)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: Theme.Space.tight)
            if isBusy {
                ProgressView()
            } else {
                Text(tier.displayPrice)
                    .font(Theme.figureSmall)
                    .monospacedDigit()
                    .foregroundStyle(Theme.glass)
            }
        }
        .padding(.horizontal, Theme.Space.base)
        .padding(.vertical, Theme.Space.snug)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }
}

// MARK: - The prompt on Results

/// The quiet row that offers the sheet, shown only after a scan that actually produced a ranking.
///
/// Whether it appears at all is `SupporterPrompt.shouldOffer`, in `Core`. This view just draws it.
struct SupporterPromptRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.snug) {
                Image(systemName: "mug.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.glass)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Buy me a drink")
                        .font(Theme.action)
                        .foregroundStyle(Theme.ink)
                    Text("ABV is free. Support it if it helped.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.vertical, Theme.Space.hair)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews
//
// Every state is reachable here without a store account, a device, or the SDK. This is what the
// in-memory double is for.

#Preview("Tiers ready") {
    PaywallView(store: SupporterStore(purchases: InMemoryPurchaseController()))
}

#Preview("Store unavailable") {
    PaywallView(store: SupporterStore(purchases: InMemoryPurchaseController(tiers: [])))
}

#Preview("Purchase fails") {
    PaywallView(store: SupporterStore(purchases: InMemoryPurchaseController(behaviour: .fails)))
}

#Preview("Ask to Buy hold") {
    PaywallView(store: SupporterStore(purchases: InMemoryPurchaseController(behaviour: .pends)))
}

#Preview("Already a supporter") {
    PaywallView(store: SupporterStore(purchases: InMemoryPurchaseController(
        status: .supporter(productIdentifier: "supporter.pint")
    )))
}

#Preview("Nothing to restore") {
    PaywallView(store: SupporterStore(purchases: InMemoryPurchaseController(priorPurchase: nil)))
}

#Preview("Prompt row") {
    List {
        SupporterPromptRow {}
    }
}
