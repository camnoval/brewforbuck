//
//  OCRDebugExportSheet.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 8/30/26.
//


import SwiftUI
import UIKit

/// Debug-only viewer for an OCR export (see `ObservationFixture`). Shows the paste-ready fixture and
/// readable dump, monospaced and selectable, with Share (to send the text to yourself / save a file)
/// and Copy. Not part of the shipping UX — reached only via the DEBUG long-press on the capture
/// screen — so it's intentionally plain.
struct OCRDebugExportSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("OCR export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = text
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        ShareLink(item: text)
                    }
                }
            }
        }
    }
}