import AppKit
import ReplayCore
import SwiftUI

/// The PDF report: one page, drawn rather than printed.
///
/// **Every WebKit route to this is dead**, and the ledger records all three: an unattached
/// `WKWebView` never finishes loading; attached, `createPDF` hangs with no timeout on the
/// call; and `printOperation(with:)` gets past loading and then paginates without end, never
/// returning while the file grows past 100 MB for a sixty-row document. Sizing the view to
/// `scrollHeight` first — the usual fix — changes nothing, and `dataWithPDF(inside:)` returns
/// an 838-byte blank because WebKit renders out of process and the `NSView` has nothing in it.
///
/// So this leaves WebKit entirely. `ImageRenderer` hands back a `CGContext`, and a PDF context
/// is a `CGContext` — which means a SwiftUI view can be drawn straight into a PDF page with no
/// browser, no layout engine and no pagination to hang on. The one page is not a limitation
/// worked around: the reference's own PDF is capped at a single page and says to use HTML for
/// longer, so this matches it.
///
/// The view is deliberately plain. It is a document that might be printed or emailed, so it
/// carries no material, no shadow and no tint — the things that make the app's surfaces read
/// on a screen are exactly the things that turn to mud on paper.
struct ReportPDFPage: View {
    let page: Report.PDF.Page

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.title)
                .font(Design.Text.pdfTitle)
                .foregroundStyle(.black)
            Text(page.summary)
                .font(Design.Text.pdfSummary)
                .foregroundStyle(.secondary)
                .padding(.top, Design.Space.snug)

            Rectangle()
                .fill(.quaternary)
                .frame(height: Design.Layout.hairline)
                .padding(.vertical, Design.Space.section)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(page.rows.enumerated()), id: \.offset) { _, entry in
                    let row = Report.PDF.row(entry)
                    HStack(alignment: .firstTextBaseline, spacing: Design.Space.card) {
                        Text(row.title)
                            .font(Design.Text.pdfRow)
                            .foregroundStyle(.black)
                            .lineLimit(1)
                        Spacer(minLength: Design.Space.inline)
                        Text(row.when)
                            .font(Design.Text.pdfRowDetail)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(row.duration)
                            .font(Design.Text.pdfRowDetail)
                            .foregroundStyle(.black)
                            .monospacedDigit()
                            .frame(width: Design.Layout.pdfDurationColumn, alignment: .trailing)
                    }
                    .frame(height: Report.PDF.rowHeight)
                }
            }

            Spacer(minLength: 0)

            if let note = page.overflowNote {
                Text(note)
                    .font(Design.Text.pdfFootnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, Design.Space.snug)
            }
            Text(page.footer)
                .font(Design.Text.pdfFootnote)
                .foregroundStyle(.tertiary)
        }
        .padding(Report.PDF.margin)
        .frame(width: Report.PDF.pageWidth, height: Report.PDF.pageHeight, alignment: .topLeading)
        // White, explicitly. A PDF has no appearance to follow, and a page that inherited
        // dark mode would print as a black rectangle.
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

enum ReportPDF {

    /// Draw one page into a PDF file.
    ///
    /// Throws rather than returning a bool so the caller can say *why* it failed. Writing a
    /// zero-byte file and reporting success is how the WebKit attempts looked from the
    /// outside for a while.
    @MainActor
    static func write(_ page: Report.PDF.Page, to url: URL) throws {
        let renderer = ImageRenderer(content: ReportPDFPage(page: page))
        // Without this the view is measured at its ideal size and the media box below no
        // longer matches what was drawn.
        renderer.proposedSize = ProposedViewSize(
            width: Report.PDF.pageWidth, height: Report.PDF.pageHeight
        )

        var failure: Error?
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(url: url as CFURL) else {
                failure = CocoaError(.fileWriteUnknown)
                return
            }
            guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
                failure = CocoaError(.fileWriteUnknown)
                return
            }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        if let failure { throw failure }
    }
}
