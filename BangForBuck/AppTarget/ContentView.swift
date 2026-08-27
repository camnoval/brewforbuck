import SwiftUI
import CoreServices

/// Root of the demo, upgraded to the *editable* results flow. The sample-menu picker stands in for
/// capture for now — it just feeds `[String]` lines into `ResultsViewModel.load(lines:)`. Next
/// conversation, `VisionTextRecognizer` output replaces `SampleMenus` and calls the same `load`;
/// `ResultsView` and the view model don't change.
struct ContentView: View {
    @StateObject private var viewModel = ResultsViewModel()
    @State private var menuIndex = 0

    var body: some View {
        NavigationStack {
            ResultsView(viewModel: viewModel)
                .navigationTitle("Bang-for-Buck")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Picker("Sample menu", selection: $menuIndex) {
                                ForEach(SampleMenus.all.indices, id: \.self) { index in
                                    Text(SampleMenus.all[index].name).tag(index)
                                }
                            }
                        } label: {
                            Label("Sample menu", systemImage: "list.bullet.rectangle")
                        }
                    }
                }
        }
        .onAppear { load() }
        .onChange(of: menuIndex) { _ in load() }
    }

    private func load() {
        viewModel.load(lines: SampleMenus.all[menuIndex].lines)
    }
}

#Preview {
    ContentView()
}
