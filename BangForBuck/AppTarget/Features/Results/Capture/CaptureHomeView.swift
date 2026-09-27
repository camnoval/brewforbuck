//
//  CaptureHomeView.swift
//  ABV
//
//  Created by Noval, Cameron on 8/27/26.
//


import SwiftUI
import PhotosUI
import UIKit
import CoreContracts
import CoreServices

/// The capture entry point (Week 1). Offers three ways to get menu lines into the same
/// `ResultsViewModel.load(lines:)` seam built earlier: scan with the camera, pick from the photo
/// library, or fall back to a bundled sample (handy for testing and a reminder that OCR is *assist*,
/// not the only way in — R1). A photo runs through `VisionTextRecognizer` off-main, then pushes the
/// editable `ResultsView`, where estimates are correctable and missing prices can be added.
struct CaptureHomeView: View {
    @StateObject private var viewModel = ResultsViewModel()

    /// The `supporter` entitlement, owned by `ABVApp`. Read here for the badge, and passed through
    /// to `ResultsView`, which is where the prompt can appear.
    @ObservedObject var supporter: SupporterStore

    /// Injected behind the contract (§6). Swap for a fake in tests; swap the OCR engine here only.
    /// `MenuTextRecognizer` runs the geometric path and, on iOS 26, Apple's document-structure path,
    /// then keeps whichever reading yields more priced drinks. On earlier systems, or if the
    /// structured pass finds no document, it is `VisionTextRecognizer` unchanged.
    private let recognizer: any TextRecognizer = MenuTextRecognizer()

    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isProcessing = false
    @State private var showResults = false
    /// Two more ways in that need no photo: type a few menu drinks, or compare packages in a store.
    @State private var showQuick = false
    @State private var showCompare = false
    /// The paywall, opened from the toolbar rather than from the earned prompt.
    @State private var showSupport = false
    @State private var errorMessage: String?

    // Debug OCR export: keep the last scanned image so its raw observations can be dumped to a
    // LineAssembler fixture (see ObservationFixture). Trigger is DEBUG-only (long-press the logo).
    @State private var lastCaptured: CapturedImage?
    @State private var exportText: String?

    private var cameraAvailable: Bool {
        DocumentScanner.isSupported || UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            // Deliberately NOT a ScrollView: the four ways in divide the whole screen, so the home
            // screen is a set of doors rather than a paragraph with small buttons under it. The
            // cards share the leftover height equally, so it fills a small phone and a large one.
            VStack(alignment: .leading, spacing: 0) {
                // The badge sits directly under the wordmark: quiet, permanent, and the first thing
                // a supporter sees on every launch. Nothing here is amber (§11).
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Wordmark(size: 40)
                        .modifier(DebugOCRExportGesture(action: exportLastScan))

                    if let kind = supporter.tierKind {
                        SupporterBadge(kind: kind)
                    }
                }

                // Says what the app does, in the user's terms. Deliberately not a question (the
                // person opened the app already) and deliberately avoids the word "value", which
                // the wordmark directly above has just said twice.
                Text("Compare the amount of standard drinks per dollar")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.tight)

                VStack(spacing: Theme.Space.snug) {
                    Button {
                        showCamera = true
                    } label: {
                        ActionCardLabel(title: "Take a photo",
                                        detail: "Scan the menu in front of you",
                                        systemImage: "camera.fill",
                                        isPrimary: true)
                    }
                    .buttonStyle(ActionCardStyle(isPrimary: true))
                    .disabled(!cameraAvailable || isProcessing)

                    PhotosPicker(selection: $libraryItem, matching: .images) {
                        ActionCardLabel(title: "Choose a photo",
                                        detail: "Use a menu shot you already have",
                                        systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(ActionCardStyle())
                    .disabled(isProcessing)

                    Button {
                        showQuick = true
                    } label: {
                        ActionCardLabel(title: "Compare two drinks",
                                        detail: "Type them in, no photo needed",
                                        systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(ActionCardStyle())
                    .disabled(isProcessing)

                    Button {
                        showCompare = true
                    } label: {
                        ActionCardLabel(title: "Compare store prices",
                                        detail: "Packs, bottles and cans by the drink",
                                        systemImage: "cart.fill")
                    }
                    .buttonStyle(ActionCardStyle())
                    .disabled(isProcessing)
                }
                .frame(maxHeight: .infinity)
                .padding(.vertical, Theme.Space.base)

                if isProcessing {
                    HStack(spacing: Theme.Space.tight) {
                        ProgressView()
                        Text("Reading the menu")
                            .font(Theme.label)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .padding(.bottom, Theme.Space.snug)
                }

                Menu {
                    ForEach(SampleMenus.all.indices, id: \.self) { index in
                        Button(SampleMenus.all[index].name) { loadSample(index) }
                    }
                } label: {
                    HStack(spacing: Theme.Space.hair) {
                        Text("Try a demo below")
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.glass)
                }
                .disabled(isProcessing)
            }
            .padding(.horizontal, Theme.Space.loose)
            .padding(.top, Theme.Space.tight)
            .padding(.bottom, Theme.Space.loose)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    supportButton
                }
            }
            .navigationDestination(isPresented: $showResults) {
                ResultsView(viewModel: viewModel, supporter: supporter)
                    .navigationTitle("Best value")
            }
            .navigationDestination(isPresented: $showQuick) {
                QuickCompareView()
            }
            .navigationDestination(isPresented: $showCompare) {
                CompareView()
            }
            .sheet(isPresented: $showCamera) {
                // The system document scanner (edge detection, perspective correction, deskew,
                // contrast, multi-page) when the device supports it; the plain camera otherwise.
                // `ignoresSafeArea` goes on each branch rather than after the `if`, because a
                // modifier trailing a `ViewBuilder` conditional has no single type to attach to.
                if DocumentScanner.isSupported {
                    DocumentScanner { pages in
                        guard !pages.isEmpty else { return }
                        process(pages: pages)
                    }
                    .ignoresSafeArea()
                } else {
                    CameraPicker { image in process(image) }
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showSupport) {
                PaywallView(store: supporter)
            }
            .sheet(isPresented: Binding(get: { exportText != nil },
                                        set: { if !$0 { exportText = nil } })) {
                if let exportText { OCRDebugExportSheet(text: exportText) }
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task { @MainActor in await loadLibrary(item) }
            }
            .alert(
                "Couldn’t read that menu",
                isPresented: Binding(get: { errorMessage != nil },
                                     set: { if !$0 { errorMessage = nil } }),
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { message in
                Text(message)
            }
            // Picks up a purchase made on another device, and a restore done elsewhere in the app.
            .task { await supporter.refresh() }
        }
    }

    // MARK: - Support

    /// The permanent way to the paywall.
    ///
    /// The earned prompt in `ResultsView` is deliberately one-shot: `SupporterPrompt` rule 2 says
    /// never ask twice, and `markAsked()` fires when the row merely *appears*. That is right for an
    /// ask, and wrong as the only door, because **`PaywallView` is where Restore Purchases lives.**
    /// App Review exercises restore on a non-consumable, and without this the restore path is
    /// reachable exactly once per install. So this is a review requirement, not a second ask.
    ///
    /// It does not re-ask anybody: `shouldOffer` still governs the prompt, and a supporter opening
    /// this sheet lands on the thank-you state rather than the tier list, because the products are
    /// non-consumables and cannot be bought twice (`MonetizationPlan.md` §3).
    ///
    /// **Labelled "Support", not "Donate", and the distinction is defensive.** Apple treats
    /// charitable donation collection differently from tipping a developer, so a button reading
    /// "Donate" invites a reviewer to read a tip jar as the former. This app already carries extra
    /// review scrutiny for its alcohol context (R3). "Support" also matches the entitlement name,
    /// the badge copy and the App Store product descriptions, so one word does all of it.
    ///
    /// Wears the tier motif from `SupporterBadge`: a mug for anyone who has not supported yet, and
    /// once they have, **their own tier's glyph** — the drop, the mug or the wineglass. Same
    /// capsule-on-a-wash treatment as the badge, so the two read as one idea. Green, never amber,
    /// because amber means "this number is an estimate" and nothing else (§11).
    private var supportButton: some View {
        Button {
            showSupport = true
        } label: {
            HStack(spacing: Theme.Space.hair) {
                Image(systemName: supporter.tierKind?.symbolName ?? "mug.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Support")
                    .font(Theme.micro)
            }
            .foregroundStyle(Theme.glass)
            .padding(.horizontal, Theme.Space.tight)
            .padding(.vertical, Theme.Space.hair)
            .background(Theme.wash(Theme.glass), in: Capsule())
        }
        .accessibilityLabel(supporter.tierKind == nil ? "Support ABV" : "Your support")
    }

    // MARK: - Inputs → the shared load(lines:) seam

    private func loadSample(_ index: Int) {
        viewModel.load(lines: SampleMenus.all[index].lines)
        showResults = true
    }

    @MainActor
    private func loadLibrary(_ item: PhotosPickerItem) async {
        defer { libraryItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "That photo couldn’t be loaded."
                return
            }
            process(image)
        } catch {
            errorMessage = "That photo couldn’t be loaded."
        }
    }

    /// A single image from the photo library, which did **not** come through the document scanner
    /// and so has had no perspective correction applied. Without rectifying it, scanning a saved
    /// photo and scanning with the camera are not the same test.
    private func process(_ image: UIImage) {
        process(pages: [image], rectify: true)
    }

    /// Runs on the main actor; Vision work happens off-main inside the recognizer, so the UI stays
    /// responsive and only the state updates hop back here.
    ///
    /// Takes *pages*, because `DocumentScanner` can return several: menus are two-sided constantly,
    /// and reading front and back into one ranking is free. Each page is recognized separately —
    /// column and row geometry is per-page and must not be mixed — and the lines are concatenated
    /// in page order, which is also the order a person would read them.
    private func process(pages: [UIImage], rectify: Bool = false) {
        let images = pages.compactMap { CapturedImage(uiImage: $0) }
        guard !images.isEmpty else {
            errorMessage = "That image couldn’t be processed."
            return
        }
        isProcessing = true
        Task { @MainActor in
            defer { isProcessing = false }
            do {
                var lines: [String] = []
                for (index, image) in images.enumerated() {
                    // Perspective correction, off the main actor, only for images the document
                    // scanner didn't already correct.
                    let prepared = rectify
                        ? CapturedImage(pngData: await ImageRectifier.rectified(pngBytes: image.pngData))
                        : image
                    if index == 0 { lastCaptured = prepared }   // DEBUG export, as OCR saw it
                    lines += try await recognizer.recognizeLines(in: prepared)
                }
                guard !lines.isEmpty else {
                    errorMessage = "No readable text found. Try a clearer, straight-on photo with good light."
                    return
                }
                viewModel.load(lines: lines)
                #if DEBUG
                // The other half of the console diagnostic. `VisionTextRecognizer` already dumps
                // observations, assembled lines and the parser trace; this adds what happened after
                // the parser — withdrawn prices, resolved ABV/size with provenance, and the ranking
                // as ordered.
                //
                // Read off the view model's own session on purpose. Rebuilding it here with
                // `MenuPipeline()` would use `StaticBeverageKnowledge`, while the screen resolves
                // through `CatalogBackedKnowledge` over the bundled catalog — so the dump would
                // disagree with the ranking it is supposed to explain, which is worse than no dump.
                // Printed immediately after `load`, before any edit can perturb it.
                print("""

                ===== BANGFORBUCK RANKING (start) =====
                \(ObservationFixture.sessionDump(viewModel.session))
                ===== BANGFORBUCK RANKING (end) =====

                """)
                #endif
                showResults = true
            } catch {
                errorMessage = "Couldn’t read that image. Try a clearer, straight-on photo."
            }
        }
    }

    // MARK: - Debug OCR export

    /// Re-run Vision on the last scanned image and build a paste-ready `LineAssembler` fixture from
    /// its raw observations. Uses `VisionTextRecognizer` directly (stateless) so it exports the real
    /// on-device OCR even if a fake recognizer were injected for the normal flow.
    private func exportLastScan() {
        guard let captured = lastCaptured else {
            errorMessage = "Scan or pick a photo first, then long-press the logo to export its OCR."
            return
        }
        Task { @MainActor in
            do {
                let observations = try await VisionTextRecognizer().recognizeObservations(in: captured)
                exportText = ObservationFixture.export(observations)
            } catch {
                errorMessage = "Couldn’t export OCR for that image."
            }
        }
    }
}

/// A no-op in release; in DEBUG it long-presses to trigger the OCR export. Keeps the debug trigger
/// out of the shipping build entirely.
private struct DebugOCRExportGesture: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        #if DEBUG
        content.onLongPressGesture(minimumDuration: 0.8, perform: action)
        #else
        content
        #endif
    }
}
