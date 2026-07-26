import Foundation

/// The two formats you would send someone: a document rather than a data file.
///
/// Markdown, CSV and JSON are for reading, importing and scripting. These two are for
/// *showing* — so they carry the app icons, a summary band, and a shape that survives being
/// opened by someone who does not have Replay.
///
/// Both are built from one body and one stylesheet, as upstream: a PDF that looks unlike
/// the HTML of the same range would be two reports, and someone would eventually notice
/// they disagreed.
extension Report {

    /// Where the app can be found, printed into a shared document so it can be acted on.
    static let storeURL = "https://www.glaze.app/app/replay-4fgahp"

    /// Resolve an application's icon to something a self-contained file can carry.
    ///
    /// A document that references icons by path stops working the moment it is emailed, so
    /// the caller inlines them as data URIs. `nil` leaves a neutral tile rather than a
    /// broken image — a missing icon should never leave a hole.
    public typealias IconResolver = (_ appPath: String?) -> String?

    /// One CSS class per distinct icon, and the rules that define them.
    ///
    /// Icons are referenced by class rather than inlined at each use because a data URI in
    /// an `<img>` tag is repeated in full every time it appears. A day with twenty sessions
    /// across a dozen apps has hundreds of app rows, and inlining per row turned a report
    /// into a **28 MB** file — the same handful of icons, embedded some three hundred times.
    /// Defined once and referenced by class, the same report is a few hundred kilobytes.
    struct IconSheet {
        var css: String
        private var classes: [String: String]

        init(entries: [Entry], resolve: IconResolver) {
            var paths: [String] = []
            var seen = Set<String>()
            for entry in entries {
                for app in entry.session.apps {
                    guard let path = app.appPath, !seen.contains(path) else { continue }
                    seen.insert(path)
                    paths.append(path)
                }
            }

            var rules: [String] = []
            var classes: [String: String] = [:]
            for (index, path) in paths.enumerated() {
                guard let uri = resolve(path) else { continue }
                let name = "ic-a\(index)"
                classes[path] = name
                rules.append(".\(name) { background-image: url(\(uri)); }")
            }
            self.classes = classes
            self.css = rules.joined(separator: "\n")
        }

        func className(for appPath: String?) -> String? {
            appPath.flatMap { classes[$0] }
        }
    }

    public static func html(
        label: String,
        entries: [Entry],
        now: Date = Date(),
        environment: Environment = .current,
        icon: IconResolver = { _ in nil }
    ) -> String {
        let sheet = IconSheet(entries: entries, resolve: icon)
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Replay — \(escapeHTML(label))</title>
        <style>
          * { box-sizing: border-box; }
          body {
            font-family: -apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
            color: #1d1d1f; margin: 0; padding: 40px 18px; background: #f0f0f4; font-size: 13px; line-height: 1.5;
          }
          .sheet {
            max-width: 760px; margin: 0 auto; background: #fff; border-radius: 16px; padding: 36px 40px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06), 0 24px 60px -34px rgba(0,0,0,0.35);
          }
        \(componentCSS)
        \(sheet.css)
        </style>
        </head>
        <body><div class="sheet">\(body(label: label, entries: entries, now: now, environment: environment, icons: sheet))</div></body>
        </html>
        """
    }

    // ── the shared body ───────────────────────────────────────────────────────

    static func body(
        label: String,
        entries: [Entry],
        now: Date,
        environment: Environment,
        icons: IconSheet
    ) -> String {
        let totalSeconds = entries.reduce(0) { $0 + $1.session.activeSeconds }
        var appNames = Set<String>()
        for entry in entries {
            for app in entry.session.apps { appNames.insert(app.applicationName) }
        }

        func tile(_ appPath: String?, large: Bool = false) -> String {
            let icon = icons.className(for: appPath).map { " \($0)" } ?? ""
            return "<span class=\"ic\(large ? " ic-lg" : "")\(icon)\"></span>"
        }

        var summary = ""
        if !entries.isEmpty {
            summary = """
            <section class="summary">
              <div class="stat"><div class="v">\(formatDurationShort(totalSeconds))</div><div class="l">Active</div></div>
              <div class="stat"><div class="v">\(entries.count)</div><div class="l">\(entries.count == 1 ? "Session" : "Sessions")</div></div>
              <div class="stat"><div class="v">\(appNames.count)</div><div class="l">\(appNames.count == 1 ? "App" : "Apps")</div></div>
            </section>
            """
            if let top = topApp(entries) {
                summary += """
                <div class="topapp">
                  \(tile(top.appPath, large: true))
                  <div class="ta-txt"><div class="ta-l">Top app</div><div class="ta-n">\(escapeHTML(top.name))</div></div>
                  <div class="ta-t">\(formatDurationShort(top.seconds))</div>
                </div>
                """
            }
        }

        var sections: [String] = []
        var currentDay = ""
        for entry in entries {
            let day = longDayLabel(entry.session.startedAt, environment)
            if day != currentDay {
                currentDay = day
                sections.append("<h2>\(escapeHTML(day))</h2>")
            }
            let appCount = entry.session.apps.count
            let meta = "\(timeLabel(entry.session.startedAt, environment)) – "
                + "\(timeLabel(entry.session.endedAt, environment)) · "
                + "\(formatDurationShort(entry.session.activeSeconds)) · "
                + "\(appCount) \(appCount == 1 ? "app" : "apps")"
            let apps = entry.session.apps.map { app in
                "<li>\(tile(app.appPath))<span class=\"nm\">\(escapeHTML(app.applicationName))</span>"
                    + "<span class=\"dur\">\(formatDurationShort(app.seconds))</span></li>"
            }.joined()

            var tags = ""
            if let list = entry.annotation?.tags, !list.isEmpty {
                tags = "<div class=\"tags\">"
                    + list.map { "<span class=\"tag\">#\(escapeHTML($0))</span>" }.joined()
                    + "</div>"
            }
            var note = ""
            let trimmed = entry.annotation?.note
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                note = "<blockquote>"
                    + escapeHTML(trimmed).replacingOccurrences(of: "\n", with: "<br>")
                    + "</blockquote>"
            }
            let star = entry.annotation?.bookmarked == true ? "<span class=\"star\">★</span>" : ""

            sections.append("""
            <section class="session">
              <div class="s-head">
                <h3>\(escapeHTML(entry.session.title))</h3>
                \(star)
              </div>
              <p class="meta">\(escapeHTML(meta))</p>
              <ul class="apps">\(apps)</ul>
              \(tags)
              \(note)
            </section>
            """)
        }
        if entries.isEmpty {
            sections.append("<p class=\"empty\">Nothing to export for this selection.</p>")
        }

        let stamp = DateFormatter()
        stamp.locale = environment.locale
        stamp.timeZone = environment.timeZone
        stamp.setLocalizedDateFormatFromTemplate("yyyyMdjmmss")

        return """
        <header>
          <div class="mark mark-empty"></div>
          <div>
            <h1>Replay <span class="scope">— \(escapeHTML(label))</span></h1>
            <div class="sub">\(entries.count) \(entries.count == 1 ? "session" : "sessions") · exported \(escapeHTML(stamp.string(from: now)))</div>
          </div>
        </header>
        <div class="rule"></div>
        \(summary)
        \(sections.joined(separator: "\n"))
        <footer>
          <div class="foot-row">
            <span>Made with Replay — a private memory of your Mac. Everything stays on this Mac.</span>
            <a href="\(storeURL)">Get Replay ↗</a>
          </div>
        </footer>
        """
    }

    /// The single application that took the most time across the whole export.
    static func topApp(_ entries: [Entry]) -> (name: String, appPath: String?, seconds: Int)? {
        var byApp: [String: (name: String, appPath: String?, seconds: Int)] = [:]
        for entry in entries {
            for app in entry.session.apps {
                let key = app.bundleIdentifier ?? app.applicationName
                if var existing = byApp[key] {
                    existing.seconds += app.seconds
                    byApp[key] = existing
                } else {
                    byApp[key] = (app.applicationName, app.appPath, app.seconds)
                }
            }
        }
        return byApp.values.max { $0.seconds < $1.seconds }
    }

    static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Shared by both documents, so the PDF and the HTML of one range cannot disagree.
    static let componentCSS = """
      * { box-sizing: border-box; }
      header { display: flex; align-items: center; gap: 13px; padding-bottom: 16px; }
      header .mark { width: 40px; height: 40px; border-radius: 9px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.18); flex: none; }
      header .mark img { width: 100%; height: 100%; object-fit: cover; }
      header .mark.mark-empty { background: linear-gradient(135deg, #5b63d3, #7d84e0); }
      header h1 { font-size: 20px; margin: 0; letter-spacing: -0.015em; font-weight: 700; }
      header h1 .scope { color: #6e6e78; font-weight: 600; }
      header .sub { color: #8e8e93; font-size: 11px; margin-top: 2px; font-variant-numeric: tabular-nums; }
      .rule { height: 3px; border-radius: 3px; background: linear-gradient(90deg, #5b63d3, #7d84e0 55%, #e9e9ef); margin-bottom: 18px; }

      .summary { display: flex; gap: 10px; margin-bottom: 10px; }
      .summary .stat { flex: 1 1 0; min-width: 0; background: #f6f6f9; border: 1px solid #ececf1; border-radius: 11px; padding: 12px 14px; }
      .summary .stat .v { font-size: 17px; font-weight: 700; letter-spacing: -0.01em; font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .summary .stat .l { color: #8e8e93; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em; margin-top: 2px; }
      .topapp { display: flex; align-items: center; gap: 11px; background: #f6f6f9; border: 1px solid #ececf1; border-radius: 11px; padding: 10px 14px; margin-bottom: 22px; }
      .topapp .ic-lg { width: 30px; height: 30px; border-radius: 7px; }
      .topapp .ta-txt { flex: 1; min-width: 0; }
      .topapp .ta-l { color: #8e8e93; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em; }
      .topapp .ta-n { font-size: 14px; font-weight: 650; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .topapp .ta-t { font-size: 14px; font-weight: 700; font-variant-numeric: tabular-nums; color: #4a4a4f; }

      h2 { font-size: 11px; text-transform: uppercase; letter-spacing: 0.09em; color: #9a9aa2; margin: 22px 0 9px; font-weight: 700; }

      .session { break-inside: avoid; background: #fbfbfc; border: 1px solid #ececf1; border-radius: 12px; padding: 14px 16px; margin-bottom: 10px; }
      .s-head { display: flex; align-items: center; gap: 7px; }
      .session h3 { font-size: 14.5px; margin: 0; font-weight: 650; letter-spacing: -0.01em; }
      .star { color: #e0a500; font-size: 13px; }
      .meta { color: #8e8e93; margin: 3px 0 11px; font-size: 11px; font-variant-numeric: tabular-nums; }

      ul.apps { list-style: none; padding: 0; margin: 0; }
      ul.apps li { display: flex; align-items: center; gap: 9px; padding: 4px 0; border-bottom: 1px solid #f1f1f4; }
      ul.apps li:last-child { border-bottom: none; }
      .ic { width: 18px; height: 18px; border-radius: 5px; overflow: hidden; flex: none; display: inline-block; background-color: #e7e7ec; background-size: contain; background-position: center; background-repeat: no-repeat; }
      ul.apps .nm { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      ul.apps .dur { color: #86868b; font-variant-numeric: tabular-nums; white-space: nowrap; }

      .tags { margin-top: 10px; display: flex; flex-wrap: wrap; gap: 5px; }
      .tag { background: #ecedfb; color: #4a51c4; font-size: 10.5px; font-weight: 600; padding: 2px 8px; border-radius: 999px; }
      blockquote { margin: 10px 0 0; padding: 7px 12px; border-left: 3px solid #c9cbf0; color: #3a3a3c; background: #f5f5fb; border-radius: 0 7px 7px 0; font-size: 11.5px; }
      .empty { color: #8e8e93; font-style: italic; }
      footer { margin-top: 26px; padding-top: 12px; border-top: 1px solid #ececef; color: #86868b; font-size: 10px; }
      .foot-row { display: flex; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
      footer a { color: #4a51c4; text-decoration: none; font-weight: 600; }
    """
}
