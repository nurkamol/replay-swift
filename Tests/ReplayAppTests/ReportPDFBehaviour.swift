@testable import ReplayUI
import CoreGraphics
import Foundation
import ReplayCore
import Testing

/// The one page of a PDF report.
///
/// The reference caps its own PDF at a single page and points the reader at HTML for
/// anything longer, so the interesting behaviour is not layout — it is what happens to the
/// rows that do not fit. A document that drops them silently is worse than no document.
@Suite("PDF report")
struct ReportPDFBehaviour {

    private let pinned = Report.Environment(
        locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!
    )

    private func entry(_ index: Int, seconds: Int = 600) -> Report.Entry {
        let start = Int64(1_700_000_000_000 + index * 3_600_000)
        return Report.Entry(
            session: ActivitySession(
                title: "Session \(index)", category: .development,
                startedAt: start, endedAt: start + Int64(seconds * 1000),
                spanSeconds: seconds, activeSeconds: seconds,
                apps: [], events: [], switches: 0
            )
        )
    }

    // MARK: - What fits

    @Test("A page holds a sensible number of rows, derived rather than picked")
    func rowsPerPage() {
        // Derived from the page and margins, so changing a margin cannot silently change how
        // much of a month somebody gets.
        #expect(Report.PDF.rowsPerPage > 10)
        #expect(Report.PDF.rowsPerPage < 40)
    }

    @Test("A short span fits whole, and says nothing about overflow")
    func fitsWhole() {
        let page = Report.PDF.page(label: "Today", entries: (0..<5).map { entry($0) },
                                   environment: pinned)
        #expect(page.rows.count == 5)
        #expect(page.omitted == 0)
        #expect(page.overflowNote == nil)
    }

    @Test("A long span is cut to the page, and the rest is accounted for")
    func overflows() {
        let total = Report.PDF.rowsPerPage + 17
        let page = Report.PDF.page(label: "This month", entries: (0..<total).map { entry($0) },
                                   environment: pinned)
        #expect(page.rows.count == Report.PDF.rowsPerPage)
        #expect(page.omitted == 17)
        // Every row is either on the page or counted in the note. Nothing vanishes.
        #expect(page.rows.count + page.omitted == total)
    }

    @Test("The overflow note names the format that carries the whole thing")
    func overflowNoteIsUseful() {
        let note = Report.PDF.overflowNote(omitted: 17)
        #expect(note.contains("17 more sessions"))
        // Telling somebody the file is truncated without telling them which file is not is
        // half an answer.
        #expect(note.contains("HTML"))
    }

    @Test("One omitted session is singular")
    func overflowSingular() {
        let note = Report.PDF.overflowNote(omitted: 1)
        #expect(note.contains("1 more session"))
        #expect(!note.contains("1 more sessions"))
    }

    // MARK: - The summary counts everything, not what fitted

    @Test("The summary describes the whole span even when the page cannot show it")
    func summaryCountsEverything() {
        let total = Report.PDF.rowsPerPage + 10
        let page = Report.PDF.page(label: "This month", entries: (0..<total).map { entry($0) },
                                   environment: pinned)
        // A summary that counted only the visible rows would disagree with the same export
        // as HTML, which is the failure that makes two formats of one report untrustworthy.
        #expect(page.summary.contains("\(total) sessions"))
    }

    @Test("Total time is the whole span's, not the visible rows'")
    func summaryTotalIsWhole() {
        let total = Report.PDF.rowsPerPage + 5
        let entries = (0..<total).map { entry($0, seconds: 3600) }
        let page = Report.PDF.page(label: "This month", entries: entries, environment: pinned)
        // total hours, not rowsPerPage hours
        #expect(page.summary.contains("\(total)h"))
    }

    @Test("One session is singular in the summary too")
    func summarySingular() {
        let page = Report.PDF.page(label: "Today", entries: [entry(0)], environment: pinned)
        #expect(page.summary.contains("1 session"))
        #expect(!page.summary.contains("1 sessions"))
    }

    // MARK: - A row

    @Test("A row's time range does not collapse its meridiem")
    func rowRangeIsDocumentStyle() {
        // `formatRange` collapses a shared meridiem — "9:11 – 9:42 AM" — which is right on a
        // card and wrong in a document. That was one of the five report divergences already
        // found against the reference, and a PDF is a document.
        let row = Report.PDF.row(entry(0), environment: pinned)
        let meridiems = row.when.components(separatedBy: "AM").count - 1
            + row.when.components(separatedBy: "PM").count - 1
        #expect(meridiems == 2)
    }

    @Test("A row carries its title and its duration")
    func rowContents() {
        let row = Report.PDF.row(entry(3, seconds: 1800), environment: pinned)
        #expect(row.title == "Session 3")
        #expect(row.duration == "30m")
    }

    // MARK: - Edges

    @Test("An empty report still produces a coherent page")
    func empty() {
        let page = Report.PDF.page(label: "Today", entries: [], environment: pinned)
        #expect(page.rows.isEmpty)
        #expect(page.omitted == 0)
        #expect(page.overflowNote == nil)
        #expect(page.summary.contains("0 sessions"))
    }

    @Test("The footer says what made the file and when")
    func footer() {
        let page = Report.PDF.page(
            label: "Today", entries: [entry(0)], environment: pinned,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(page.footer.hasPrefix("Replay · "))
        #expect(page.footer.count > "Replay · ".count)
    }
}

/// The renderer itself, which is the half that three WebKit attempts never reached.
///
/// These write a real file and read it back with Core Graphics. A PDF export that produces a
/// zero-byte file, or a blank page, or twelve pages, all "succeed" from the caller's side —
/// which is exactly how the `dataWithPDF` attempt looked before somebody opened the result.
@Suite("PDF rendering")
@MainActor
struct ReportPDFRendering {

    private func entry(_ index: Int) -> Report.Entry {
        let start = Int64(1_700_000_000_000 + index * 3_600_000)
        return Report.Entry(
            session: ActivitySession(
                title: "Session \(index)", category: .development,
                startedAt: start, endedAt: start + 600_000,
                spanSeconds: 600, activeSeconds: 600,
                apps: [], events: [], switches: 0
            )
        )
    }

    private func render(_ count: Int) throws -> CGPDFDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("replay-pdf-\(count)-\(UUID().uuidString).pdf")
        let page = Report.PDF.page(label: "Test report", entries: (0..<count).map { entry($0) })
        try ReportPDF.write(page, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let document = CGPDFDocument(url as CFURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return document
    }

    @Test("It writes a PDF that Core Graphics can open")
    func writesAValidPDF() throws {
        _ = try render(5)
    }

    @Test("One page, whatever it was given")
    func alwaysOnePage() throws {
        // The failure that killed `printOperation` was pagination without end — a sixty-row
        // document past 100 MB. One page is the whole design.
        #expect(try render(3).numberOfPages == 1)
        #expect(try render(Report.PDF.rowsPerPage + 50).numberOfPages == 1)
    }

    @Test("The page is the size it claims to be")
    func pageSize() throws {
        let document = try render(5)
        let box = try #require(document.page(at: 1)).getBoxRect(.mediaBox)
        #expect(abs(box.width - Report.PDF.pageWidth) < 1)
        #expect(abs(box.height - Report.PDF.pageHeight) < 1)
    }

    @Test("It is not the 838-byte blank the WebKit route produced")
    func hasContent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("replay-pdf-size-\(UUID().uuidString).pdf")
        try ReportPDF.write(
            Report.PDF.page(label: "Test", entries: (0..<10).map { entry($0) }), to: url
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size > 2_000)
    }

    @Test("An empty report still writes an openable page")
    func empty() throws {
        #expect(try render(0).numberOfPages == 1)
    }
}
