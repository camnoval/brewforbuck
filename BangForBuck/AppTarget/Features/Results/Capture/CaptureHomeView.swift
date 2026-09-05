//
//  CaptureHomeView.swift
//  BangForBuck
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

    /// Injected behind the contract (§6). Swap for a fake in tests; swap the OCR engine here only.
    private let recognizer: any TextRecognizer = VisionTextRecognizer()

    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isProcessing = false
    @State private var showResults = false
    /// The store calculator — a second way in that needs no photo at all (typed prices only).
    @State private var showCompare = false
    @State private var errorMessage: String?

    // Debug OCR export: keep the last scanned image so its raw observations can be dumped to a
    // LineAssembler fixture (see ObservationFixture). Trigger is DEBUG-only (long-press the logo).
    @State private var lastCaptured: CapturedImage?
    @State private var exportText: String?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "menucard")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .modifier(DebugOCRExportGesture(action: exportLastScan))
                Text("Scan a drink menu")
                    .font(.title2).bold()
                Text("Get the alcoholic options ranked by how much you get per dollar. Anything we estimate is flagged and you can correct it.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take a photo", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!cameraAvailable || isProcessing)

                    PhotosPicker(selection: $libraryItem, matching: .images) {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isProcessing)

                    Button {
                        showCompare = true
                    } label: {
                        Label("Compare store prices", systemImage: "cart")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isProcessing)

                    Menu {
                        ForEach(SampleMenus.all.indices, id: \.self) { index in
                            Button(SampleMenus.all[index].name) { loadSample(index) }
                        }
                    } label: {
                        Text("Try a sample menu")
                            .font(.footnote)
                    }
                    .disabled(isProcessing)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)

                if isProcessing {
                    ProgressView("Reading menu…").padding(.top, 8)
                }

                Spacer()
            }
            .navigationTitle("Bang-for-Buck")
            .navigationDestination(isPresented: $showResults) {
                ResultsView(viewModel: viewModel).navigationTitle("Results")
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
            .onChange(of: libraryItem) { item in
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
