import Foundation
import Vision
import UIKit
import CoreContracts
import CoreModel
import CoreServices

// ─────────────────────────────────────────────────────────────────────────────────────────────────
// ⚠️ UNVERIFIED API SURFACE — check these seven names in Xcode before trusting this file.
//
// Everything Vision-specific in this file is deliberately confined to `candidateReadings`, and the
// whole type is behind `#available` with a fallback, so if a name is wrong the fix is local and the
// shipping path is untouched. The names, from Apple's docs (iOS 26) rather than from a compile:
//
//   1. RecognizeDocumentsRequest()                  — init
//   2. request.perform(on: cgImage)                 — returns [DocumentObservation]; if it returns a
//                                                     single observation, drop the `.first`
//   3. observation.document                         — DocumentObservation.Container
//   4. container.text.transcript                    — String, all text in reading order
//   5. container.tables                             — [DocumentObservation.Container.Table]
//   6. table.rows                                   — [[Table.Cell]]
//   7. cell.content.text.transcript                 — String
//
// If `transcript` turns out NOT to be newline-segmented, switch `pageReading()` to
// `container.text.lines` and read each `RecognizedTextObservation` via `topCandidates(1)`.
// ─────────────────────────────────────────────────────────────────────────────────────────────────

/// OCR by **document structure** rather than by geometry (iOS 26+).
///
/// The geometric path has one irreducible weakness, and it cost a whole menu: a single column of
/// right-aligned prices is the same *shape* as two columns, so `LineAssembler` can cut the page down
/// the price gutter and strand every price. `minNameFraction` now vetoes that, but the deeper fix is
/// not to infer the table in the first place — Apple's `RecognizeDocumentsRequest` reports it. A
/// numbered tap list (`1 │ NORTH COUNTRY BUCKSNORT STOUT 6.9% ABV │ $5`) is literally a three-column
/// table, and a two-row item (`BLUE MOON $6` / `(BELGIAN WHEAT) 5.4% ABV`) is literally a paragraph.
///
/// This emits **two independent candidate readings** rather than trying to interleave tables with
/// prose. Interleaving would need each element's bounding region and a reading-order sort, which is
/// exactly the kind of geometry this type exists to stop hand-rolling; two self-consistent readings
/// judged by `MenuReadSelection` gets the same result with none of that:
///
///  - **page reading** — the document's own text in its own reading order. Beats the geometric path
///    on multi-column pages because the column model is Vision's, not ours.
///  - **table reading** — one line per table row, cells joined. Beats everything on a grid, and
///    loses on a mixed menu because it drops the prose sections. It is *supposed* to lose there:
///    `MenuReadSelection` scores by priced drinks, so the grid-only reading wins exactly on the
///    menus that are a grid.
@available(iOS 26.0, *)
struct DocumentStructureRecognizer: TextRecognizer {

    enum RecognizerError: Error { case invalidImageData, noDocument }

    func recognizeLines(in image: CapturedImage) async throws -> [String] {
        MenuReadSelection.best(of: try await candidateReadings(in: image))
    }

    /// Every distinct reading this engine can offer, best-first is NOT required — the caller scores
    /// them. Returns `[]` when Vision finds no document, which is a legitimate outcome on a badly
    /// angled photo and the caller's cue to fall back.
    func candidateReadings(in image: CapturedImage) async throws -> [[String]] {
        guard let cgImage = UIImage(data: Data(image.pngData))?.cgImage else {
            throw RecognizerError.invalidImageData
        }

        let request = RecognizeDocumentsRequest()
        let observations = try await request.perform(on: cgImage)
        guard let document = observations.first?.document else { return [] }

        var readings: [[String]] = []

        let page = Self.split(document.text.transcript)
        if !page.isEmpty { readings.append(page) }

        let tableRows = document.tables.flatMap { table in
            table.rows.map { row in
                row.map { $0.content.text.transcript }
                    .map { Self.collapseWhitespace($0) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
        }.filter { !$0.isEmpty }
        if !tableRows.isEmpty { readings.append(tableRows) }

        #if DEBUG
        print("""

        ===== BANGFORBUCK DOC STRUCTURE (start) =====
        # \(document.tables.count) tables, \(document.paragraphs.count) paragraphs, \
        \(document.lists.count) lists
        # page reading: \(page.count) lines, score \(MenuReadSelection.score(page))
        # table reading: \(tableRows.count) rows, score \(MenuReadSelection.score(tableRows))
        \(tableRows.map { "  ROW  " + $0 }.joined(separator: "\n"))
        ===== BANGFORBUCK DOC STRUCTURE (end) =====

        """)
        #endif

        return readings
    }

    /// Newline-separated transcript → trimmed, non-empty lines.
    static func split(_ transcript: String) -> [String] {
        transcript
            .split(whereSeparator: \.isNewline)
            .map { collapseWhitespace(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// A cell's transcript can carry its own newlines and padding; the parser wants one flat line.
    static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

/// Runs every available reader on the photo and keeps whichever reading yields the most priced
/// drinks (`MenuReadSelection`).
///
/// **Why both, every time, rather than "structure if iOS 26 else geometry".** They fail on different
/// menus, so preferring one by version is a coin flip per photo; scoring both is a decision. The
/// cost is one extra on-device Vision pass per scan — hundreds of milliseconds, once, on a screen
/// where the person has just taken a photo and expects a moment's work — against the failure it
/// prevents, which is a menu that ranks nothing. R1 says OCR is assist and a partial read must still
/// be useful; this is the cheapest way to stop a *total* read failure being the thing that ships.
///
/// The geometric reading is passed **first**, so a tie leaves the proven path in charge.
struct MenuTextRecognizer: TextRecognizer {
    private let geometric = VisionTextRecognizer()

    func recognizeLines(in image: CapturedImage) async throws -> [String] {
        // The proven path is also the floor: if everything else throws or finds nothing, this is
        // still exactly today's behaviour.
        let baseline = try await geometric.recognizeLines(in: image)
        var candidates: [[String]] = [baseline]

        // Vision's language correction biases toward dictionary words. A menu is mostly brand
        // names, so it may well be hurting. This costs one more on-device pass and needs no
        // judgement call from us — the reading that yields more priced drinks wins.
        if let uncorrected = try? await geometric.recognizeLinesWithoutLanguageCorrection(in: image),
           !uncorrected.isEmpty {
            candidates.append(uncorrected)
        }

        if #available(iOS 26.0, *) {
            let structured = (try? await DocumentStructureRecognizer().candidateReadings(in: image)) ?? []
            candidates += structured.filter { !$0.isEmpty }
        }

        guard candidates.count > 1 else { return baseline }
        let chosen = MenuReadSelection.best(of: candidates)
        #if DEBUG
        print("""
        ===== BANGFORBUCK READ SELECTION =====
        \(candidates.enumerated().map { index, reading in
            let label = index == 0 ? "geometric" : (index == 1 ? "no-lang-correction" : "structured \(index - 1)")
            return "# \(label): \(reading.count) lines, score \(MenuReadSelection.score(reading))"
        }.joined(separator: "\n"))
        # chosen: \(chosen.count) lines
        """)
        #endif
        return chosen
    }
}
