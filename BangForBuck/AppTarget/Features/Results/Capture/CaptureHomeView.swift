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
    private let recognizer: any TextRecognizer = VisionTextRecognizer()

    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isProcessing = false
    @State private var showResults = false
    /// Two more ways in that need no photo: type a few menu drinks, or compare packages in a store.
    @State private var showQuick = false
    @State private var showCompare = false
    @State private var errorMessage: String?

    // Debug OCR export: keep the last scanned image so its raw observations can be dumped to a
    // LineAssembler fixture (see ObservationFixture). Trigger is DEBUG-only (long-press the logo).
    @State private var lastCaptured: CapturedImage?
    @State private var exportText: String?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

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
                CameraPicker { image in process(image) }
                    .ignoresSafeArea()
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

    /// Runs on the main actor; Vision work happens off-main inside the recognizer, so the UI stays
    /// responsive and only the state updates hop back here.
    private func process(_ image: UIImage) {
        guard let captured = CapturedImage(uiImage: image) else {
            errorMessage = "That image couldn’t be processed."
            return
        }
        lastCaptured = captured   // for the DEBUG OCR export
        isProcessing = true
        Task { @MainActor in
            defer { isProcessing = false }
            do {
                let lines = try await recognizer.recognizeLines(in: captured)
                guard !lines.isEmpty else {
                    errorMessage = "No readable text found. Try a clearer, straight-on photo with good light."
                    return
                }
                viewModel.load(lines: lines)
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
