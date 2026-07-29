import Foundation
import ReplayCore

/// The parity checks, as data — so the same suite can run two ways.
///
/// `swift test` runs it through swift-testing, which needs Xcode. `swift run
/// replay-parity` runs it as a plain executable, which does not. Both call
/// ``ParityKit/runAllChecks(specRoot:)`` and get identical results, so there is no
/// second implementation to keep in step.
///
/// Everything is measured against `spec/`, generated from the Glaze app by
/// `tools/sync-spec.mjs`. See docs/SYNC.md.
public enum ParityKit {

    // ── the generated contract ────────────────────────────────────────────────

    public struct Fixture: Decodable, Sendable {
        public struct Event: Decodable, Sendable {
            public let id: Int64
            public let type: String
            public let applicationName: String
            public let bundleIdentifier: String?
            public let appPath: String?
            public let startedAt: Int64
            public let endedAt: Int64?
            public let duration: Int
        }
        public struct App: Decodable, Sendable {
            public let applicationName: String
            public let bundleIdentifier: String?
            public let seconds: Int
            public let switches: Int
            public let share: Double
        }
        public struct Item: Decodable, Sendable {
            public let kind: String
            public let title: String?
            public let category: String?
            public let spanSeconds: Int?
            public let activeSeconds: Int?
            public let switches: Int?
            public let eventIds: [Int64]?
            public let apps: [App]?
            public let reason: String?
            public let applicationName: String?
            public let startedAt: Int64
            public let endedAt: Int64
            public let seconds: Int?
        }
        /// What `computeDaySummary` produced for the same input — the figures Today
        /// leads with, so a drift here is visible on the first screen of the app.
        public struct Summary: Decodable, Sendable {
            public struct Focus: Decodable, Sendable {
                public let averageStretchSeconds: Int
                public let quality: String
            }
            public struct TopApp: Decodable, Sendable {
                public let applicationName: String
                public let seconds: Int
            }
            public let activeSeconds: Int
            public let activeLabel: String
            public let appsUsed: Int
            public let sessionCount: Int
            public let switches: Int
            public let focus: Focus?
            public let mostUsed: TopApp?
            public let longestSessionSeconds: Int?
        }
        /// The timezone the fixture was generated under. Session titles are named after
        /// the *local* day part, so deriving in any other zone renames them.
        public let timeZone: String
        public let name: String
        public let description: String
        public let now: Int64
        public let events: [Event]
        public let expected: [Item]
        public let summary: Summary
    }

    public struct Constants: Decodable, Sendable {
        public struct Tracker: Decodable, Sendable {
            public let awayAfterSeconds: Int
            public let idlePollMs: Int
            public let pointEventDedupeMs: Int
            public let ignoredBundleIds: [String]
        }
        public struct Store: Decodable, Sendable {
            public let idleStretchSeconds: Int
            public let compactMinFreeRatio: Double
            public let compactMinFreePages: Int
            public let deleteChunk: Int
        }
        public struct CategoryPattern: Decodable, Sendable {
            public let category: String
            public let pattern: String
        }
        public struct Derivation: Decodable, Sendable {
            public let idleBreakSeconds: Int
            public let recordingGapSeconds: Int
            public let minSessionSeconds: Int
            public let categoryPatterns: [CategoryPattern]
        }
        public struct BackupInfo: Decodable, Sendable {
            public let format: String
            public let version: Int
            public let acceptedEventTypes: [String]
        }
        public struct Annotations: Decodable, Sendable {
            public let maxTagLength: Int
            public let maxTags: Int
        }
        public struct Motion: Decodable, Sendable {
            public let pressMs: Int
            public let hoverMs: Int
            public let enterMs: Int
            public let easeSoft: [Double]
            public let easeStandard: [Double]
            public let enterStepMs: Int
            public let enterCapMs: Int
        }
        public struct FocusGoal: Decodable, Sendable {
            public let presetMinutes: [Int]
            public let minCustomMinutes: Int
            public let maxCustomMinutes: Int
        }
        public let glazeVersion: String
        public let glazeCommit: String
        public let tracker: Tracker
        public let store: Store
        public let derivation: Derivation
        public let backup: BackupInfo
        public let annotations: Annotations
        public let focusGoal: FocusGoal
        public let playback: PlaybackConstants

        public struct PlaybackConstants: Decodable, Sendable {
            public let baseDurationMillis: Int
            public let speeds: [Int]
        }
        public let apps: AppsConstants
        public let week: WeekConstants

        public struct AppsConstants: Decodable, Sendable {
            public let windows: [Window]

            public struct Window: Decodable, Sendable {
                public let value: String
                public let label: String
                public let days: Int
                public let subtitle: String
            }
        }

        public struct WeekConstants: Decodable, Sendable {
            public let workflowLimit: Int
            public let appLimit: Int
            public let arcTicks: [Int]
        }

        public let deletion: DeletionConstants

        public struct DeletionConstants: Decodable, Sendable {
            public let deletableDaysWindow: Int
        }

        public let dockBadge: DockBadgeConstants

        public struct DockBadgeConstants: Decodable, Sendable {
            public let hourSeconds: Int
            public let minimumHours: Int
        }

        public let today: TodayConstants

        public struct TodayConstants: Decodable, Sendable {
            public let eveningFromHour: Int
            public let eveningPrompt: String
            public let prompt: String
            public let heroRecentHours: Int
            public let reflectionLookbackDays: Int
            public let heroOrder: [String]
        }

        public let search: SearchConstants
        public let timeline: TimelineConstants

        public struct SearchConstants: Decodable, Sendable {
            public let resultStepMs: Int
            public let resultCapMs: Int
            public let days: Int
            public let conceptLimit: Int
            public let spans: [Span]
            public let weekDaysBack: Int
            public let monthDaysBack: Int

            public struct Span: Decodable, Sendable {
                public let value: String
                public let label: String
            }
        }

        public struct TimelineConstants: Decodable, Sendable {
            public let order: [String]
            public let ranges: [Range]
            public let defaultRange: String

            public struct Range: Decodable, Sendable {
                public let key: String
                public let days: Int
                public let label: String
                public let subtitle: String
                public let keepDayLabels: [String]?
            }
        }

        public let screensaver: ScreensaverConstants

        public struct ScreensaverConstants: Decodable, Sendable {
            public let driftSeconds: Int
            public let reducedSeconds: Int
            public let breatheSeconds: Int
            public let breatheScale: Double
            public let breatheFloor: Double
        }

        public let tray: TrayConstants

        public struct TrayConstants: Decodable, Sendable {
            public let recentLimit: Int
            public let recentHours: Int
            public let paused: String
            public let away: String
            public let waiting: String
            public let focusedFor: String
            public let recentHeading: String
            public let justNow: String
            public let tooltipPaused: String
            public let tooltipTracking: String
            public let symbol: String
        }

        public let heatmap: HeatmapConstants

        public struct HeatmapConstants: Decodable, Sendable {
            public let lowSeconds: Int
            public let midSeconds: Int
            public let highSeconds: Int
            public let levelMix: [Int]
            public let weekBackDays: Int
            public let monthBackDays: Int
            public let yearBackDays: Int
            public let yearWeeks: Int
            public let monthCells: Int
            public let yearSquare: Int
            public let monthLabelMaxDate: Int
        }

        public let canvas: CanvasConstants

        public struct CanvasConstants: Decodable, Sendable {
            public let unfocusedOpacity: Double
            public let appsFadedBelowZoom: Double
            public let appFadedOpacity: Double
            public let appLabelsFromZoom: Double
            public let tourDwellMillis: Int
            public let tourNeighbours: Int
            public let tourCameraMillis: Int
            public let tourEndZoom: Double
            public let tourStepZoom: Double
            public let focusZoom: Double
            public let centreZoom: Double
            public let centreMillis: Int
            public let cameraMillis: Int
            public let zoomButtonStep: Double
            public let zoomButtonMillis: Int
            public let minZoom: Double
            public let maxZoom: Double
            public let glideMinSpeed: Double
            public let glideDecay: Double
            public let glideRestSpeed: Double
            public let wheelStep: Double
            public let wheelSensitivity: Double
        }
        public let motion: Motion
    }

    /// Every labelled row in the reference's Settings, and the line under it. See
    /// `spec/settings-copy.json`.
    public struct SettingsCopySpec: Decodable, Sendable {
        public struct Row: Decodable, Sendable {
            public let label: String
            public let description: String?
        }
        public let rows: [Row]
    }

    /// The Guide's sixteen questions and answers, lifted whole from the reference. The
    /// largest body of copy in the app, and all of it read by a person. See `spec/guide.json`.
    public struct GuideSpec: Decodable, Sendable {
        public struct Entry: Decodable, Sendable {
            public let question: String
            public let answer: String
        }
        public let entries: [Entry]
    }

    /// The narrative surfaces' own words — Story's hub and rituals, and the subtitles,
    /// empty states and footnotes of Chapters and Autobiography. Almost the whole of those
    /// three screens is prose, and until 2026-07-28 nothing held any of it: every sentence
    /// was a paraphrase and both footnotes were missing. See `spec/narrative-copy.json`.
    public struct NarrativeCopySpec: Decodable, Sendable {
        public struct Hub: Decodable, Sendable {
            public let title: String
            public let detail: String
        }
        public struct Story: Decodable, Sendable {
            public let title: String
            public let subtitle: String
            public let hub: [Hub]
            public let ritualsLabel: String
            public let ritualsFootnote: String
            public let ritualsEmptyTitle: String
            public let ritualsEmptyDetail: String
        }
        public struct Chapters: Decodable, Sendable {
            public let subtitle: String
            public let emptyTitle: String
            public let emptyDetail: String
        }
        public struct Autobiography: Decodable, Sendable {
            public let subtitle: String
            public let emptyTitle: String
            public let emptyDetail: String
            public let footnote: String
        }
        public struct Museum: Decodable, Sendable {
            public let subtitle: String
            public let sections: [String]
            public let emptyTitle: String
            public let emptyDetail: String
        }
        public struct Legacy: Decodable, Sendable {
            public let subtitle: String
            public let sections: [String]
            public let emptyTitle: String
            public let emptyDetail: String
        }
        public struct Empty: Decodable, Sendable {
            public let emptyTitle: String
            public let emptyDetail: String
        }
        public let story: Story
        public let chapters: Chapters
        public let autobiography: Autobiography
        public let museum: Museum
        public let legacy: Legacy
        public let appHistory: Empty
        public let relationship: Empty
    }

    /// Day grouping and report text, run against the real Glaze code under a pinned clock,
    /// timezone and locale. See `spec/grouping-and-export.json`.
    public struct GroupingAndExport: Decodable, Sendable {
        public struct Group: Decodable, Sendable {
            public let dayStart: Int64
            public let eventIds: [Int64]
        }
        public struct Grouping: Decodable, Sendable {
            public let events: [Fixture.Event]
            public let expected: [Group]
        }
        public struct Annotation: Decodable, Sendable {
            public let sessionStart: Int64
            public let note: String
            public let bookmarked: Bool
            public let tags: [String]
        }
        public struct Reports: Decodable, Sendable {
            public let markdown: String
            public let csv: String
            public let json: String
        }
        public struct ReportCase: Decodable, Sendable {
            public let label: String
            public let now: Int64
            public let events: [Fixture.Event]
            public let annotations: [Annotation]
            public let expected: Reports
        }
        public struct Stories: Decodable, Sendable {
            public struct Case: Decodable, Sendable {
                public let name: String
                public let now: Int64
                public let events: [Fixture.Event]
            }
            public struct Expected: Decodable, Sendable {
                public let name: String
                public let sessionCount: Int
                public let sentences: [String]
            }
            public let cases: [Case]
            public let expected: [Expected]
        }
        public struct CollectionsCase: Decodable, Sendable {
            public struct Definition: Decodable, Sendable {
                public let category: String
                public let label: String
            }
            public struct App: Decodable, Sendable {
                public let applicationName: String
                public let seconds: Int
            }
            public struct Expected: Decodable, Sendable {
                public let category: String
                public let label: String
                public let sessionCount: Int
                public let totalSeconds: Int
                public let apps: [App]
            }
            public let events: [Fixture.Event]
            public let now: Int64
            public let definitions: [Definition]
            public let sessionCount: Int
            public let expected: [Expected]
        }
        public struct HistoryCase: Decodable, Sendable {
            public struct Target: Decodable, Sendable {
                public let key: String
                public let label: String
                public let dayStart: Int64
            }
            public struct Found: Decodable, Sendable {
                public let key: String
                public let dayStart: Int64
                public let activeSeconds: Int
            }
            public let now: Int64
            public let targets: [Target]
            public let found: [Found]
        }
        public struct History: Decodable, Sendable {
            public struct Summary: Decodable, Sendable {
                public let dayStart: Int64
                public let activeSeconds: Int
                public let topAppName: String?
            }
            public let summaries: [Summary]
            public let cases: [HistoryCase]
        }
        public struct SearchCase: Decodable, Sendable {
            public struct Result: Decodable, Sendable {
                public let matches: [Int64]
                public let usesApp: [Int64]
            }
            public let queries: [String]
            public let expected: [String: Result]
        }
        public struct Scopes: Decodable, Sendable {
            public let events: [Fixture.Event]
            public let now: Int64
            public let todayStart: Int64
            public let annotations: [Annotation]
            /// Every scope the reference offers, so one added upstream shows up as a key
            /// this port does not handle rather than as silence.
            public let offered: [String]
            public let allSessionStarts: [Int64]
            public let expected: [String: [Int64]]
        }
        public struct WeekCase: Decodable, Sendable {
            public struct Expected: Decodable, Sendable {
                public struct Day: Decodable, Sendable {
                    public let dayStart: Int64
                    public let weekdayShort: String
                    public let dayOfMonth: Int
                    public let activeSeconds: Double
                    public let sessionCount: Int
                    public let arc: [Double]
                    public let isToday: Bool
                    public let isEmpty: Bool
                }
                public struct App: Decodable, Sendable {
                    public let applicationName: String
                    public let bundleIdentifier: String?
                    public let seconds: Int
                    public let share: Double
                    public let daysUsed: Int
                }
                public struct Peak: Decodable, Sendable {
                    public let weekday: Int
                    public let hour: Int
                    public let seconds: Double
                }
                public let days: [Day]
                public let activeSeconds: Int
                public let activeLabel: String
                public let sessionCount: Int
                public let appsUsed: Int
                public let apps: [App]
                public let rhythm: [[Double]]
                public let peak: Peak?
                public let peakLabel: String?
            }
            public struct PeakCase: Decodable, Sendable {
                public let weekday: Int
                public let hour: Int
                public let seconds: Int
                public let label: String
            }
            public let events: [Fixture.Event]
            public let dayStarts: [Int64]
            public let now: Int64
            public let expected: Expected
            public let peakCases: [PeakCase]
        }

        public struct CanvasCase: Decodable, Sendable {
            public struct Constellation: Decodable, Sendable {
                public struct Node: Decodable, Sendable {
                    public let key: String
                    public let totalSeconds: Int
                    public let sessionCount: Int
                }
                public struct Edge: Decodable, Sendable {
                    public let a: String
                    public let b: String
                    public let weight: Int
                }
                public let nodes: [Node]
                public let edges: [Edge]
                public let maxWeight: Int
            }
            public struct Graph: Decodable, Sendable {
                public struct Node: Decodable, Sendable {
                    public let id: String
                    public let type: String
                    public let label: String
                    public let subtitle: String
                    public let weight: Int
                    public let ref: String
                }
                public struct Edge: Decodable, Sendable {
                    public let a: String
                    public let b: String
                    public let weight: Int
                    public let kind: String
                }
                public let nodes: [Node]
                public let edges: [Edge]
                public let maxAppWeight: Int
            }
            public let constellation: Constellation
            public let expected: Graph
        }

        public struct BriefingCase: Decodable, Sendable {
            public struct Input: Decodable, Sendable {
                public struct MonthAgo: Decodable, Sendable {
                    public let dayStart: Int64
                    public let topApp: String?
                }
                public let name: String
                public let now: Int64
                public let yesterdayEvents: [Fixture.Event]
                public let monthAgo: MonthAgo?
                public let bookmarkStarts: [Int64]?
            }
            public struct Result: Decodable, Sendable {
                public struct Project: Decodable, Sendable {
                    public let id: String
                    public let name: String
                }
                public let dayStart: Int64
                public let yesterdayActiveSeconds: Int
                public let yesterdayTopApp: String?
                public let longestFocusSeconds: Int?
                public let continuedProject: Project?
                public let pendingBookmark: Int64?
            }
            public struct Expected: Decodable, Sendable {
                public let name: String
                public let result: Result?
            }
            public struct Summary: Decodable, Sendable {
                public let dayStart: Int64
                public let activeSeconds: Int
                public let topBundleId: String?
                public let topAppName: String?
                public let topSeconds: Int
            }
            public let cases: [Input]
            public let summaries: [Summary]
            public let expected: [Expected]
        }

        public struct MemoryCase: Decodable, Sendable {
            public struct Part: Decodable, Sendable {
                public let signal: Double
                public let weight: Double
            }
            public struct SessionInput: Decodable, Sendable {
                public let activeSeconds: Int
                public let bookmarked: Bool?
                public let hasNote: Bool?
            }
            public struct ProjectInput: Decodable, Sendable {
                public let totalSeconds: Int
                public let sessionCount: Int
            }
            public struct Cases: Decodable, Sendable {
                public let clamp: [Double]
                public let ramps: [[Double]]
                public let freshness: [[Double]]
                public let blends: [[Part]]
                public let days: [[Int64]]
                public let sessions: [SessionInput]
                public let projects: [ProjectInput]
                public let thresholds: [Double]
            }
            public struct Scoring: Decodable, Sendable {
                public let clamp: [Double]
                public let ramps: [Double]
                public let freshness: [Double]
                public let blends: [Double]
                public let days: [Double]
                public let sessions: [Double]
                public let projects: [Double]
                public let labels: [String]
            }
            public struct Candidate: Decodable, Sendable {
                public let id: String
                public let confidence: Double
            }
            public struct Options: Decodable, Sendable {
                public let threshold: Double
                public let dismissed: [String]?
                public let archived: [String]?
            }
            public struct SelectionInput: Decodable, Sendable {
                public let name: String
                public let candidates: [Candidate]
                public let options: Options
            }
            public struct SelectionResult: Decodable, Sendable {
                public let name: String
                public let eligible: [String]
                public let chosen: String?
            }
            public struct App: Decodable, Sendable {
                public let applicationName: String
                public let bundleIdentifier: String?
                public let seconds: Int
            }
            public struct ProjectFixture: Decodable, Sendable {
                public struct Session: Decodable, Sendable { public let startedAt: Int64 }
                public let id: String
                public let name: String
                public let apps: [App]
                public let totalSeconds: Int
                public let sessionCount: Int
                public let firstSeen: Int64
                public let lastActive: Int64
                public let sessions: [Session]
            }
            public struct Produced: Decodable, Sendable {
                public let id: String
                public let kind: String
                public let confidence: Double
                public let headline: String
                public let detail: String?
            }
            public struct Producers: Decodable, Sendable {
                public let rightTime: Produced?
                public let thread: Produced?
                public let echo: Produced?
            }
            public let scoringCases: Cases
            public let scoring: Scoring
            public let selectionCases: [SelectionInput]
            public let selection: [SelectionResult]
            public let projects: [ProjectFixture]
            public let now: Int64
            public let rightTimeEvents: [Fixture.Event]
            public let echoEvents: [Fixture.Event]
            public let producers: Producers
            public let anniversaryNow: Int64
            public let anniversarySeed: MomentsCase.Seed
            public let bookmarks: [Bookmark]
            public let reflections: [Reflection]
            public let surprise: [Int64]
            public let anniversaries: [Produced]
            public let forgotten: [Produced]

            public struct Bookmark: Decodable, Sendable {
                public let sessionStart: Int64
                public let note: String
                public let bookmarked: Bool
                public let updatedAt: Int64
            }
            public struct Reflection: Decodable, Sendable {
                public let dayStart: Int64
                public let text: String
            }
        }

        public struct MomentsCase: Decodable, Sendable {
            public struct Seed: Decodable, Sendable {
                public struct FirstSeen: Decodable, Sendable {
                    public let applicationName: String
                    public let bundleIdentifier: String
                    public let firstAt: Int64
                }
                public let firstEventAt: Int64?
                public let appCount: Int
                public let appFirstSeen: [FirstSeen]
            }
            public struct Expected: Decodable, Sendable {
                public let kind: String
                public let key: String
                public let title: String
                public let detail: String
                public let dayStart: Int64?
            }
            public let events: [Fixture.Event]
            public let now: Int64
            public let seed: Seed
            public let expected: [Expected]
            public let quoteKey: String?
        }

        public struct RelationshipsCase: Decodable, Sendable {
            public struct Partner: Decodable, Sendable {
                public let applicationName: String
                public let switches: Int
                public let sharedSessions: Int
                public let forward: Int
                public let backward: Int
                public let avgTogetherSeconds: Int
            }
            public struct Pair: Decodable, Sendable {
                public let switches: Int
                public let aToB: Int
                public let bToA: Int
                public let sharedSessions: Int
                public let avgTogetherSeconds: Int
                public let sessionStarts: [Int64]
            }
            public let anchorKey: String
            public let partnerKey: String
            public let partners: [Partner]
            public let relationship: Pair?
            public let hasNoRelationship: Bool
        }

        public struct LegacyCase: Decodable, Sendable {
            public struct App: Decodable, Sendable {
                public let bundleId: String
                public let name: String
                public let seconds: Int
                public let days: Int
            }
            public struct Expected: Decodable, Sendable {
                public let firstDay: Int64
                public let lastDay: Int64
                public let totalSeconds: Int
                public let activeDays: Int
                public let years: [Int]
                public let favorites: [App]
            }
            public let expected: Expected?
        }

        public struct AutobiographyCase: Decodable, Sendable {
            public struct Expected: Decodable, Sendable {
                public struct App: Decodable, Sendable {
                    public let applicationName: String
                    public let days: Int
                }
                public struct BusiestDay: Decodable, Sendable {
                    public let day: Int64
                    public let activeSeconds: Int
                }
                public let key: String
                public let kind: String
                public let start: Int64
                public let end: Int64
                public let label: String
                public let activeDays: Int
                public let totalActiveSeconds: Int
                public let dominantCategory: String?
                public let topApps: [App]
                public let busiestDay: BusiestDay?
                public let reflectionCount: Int
                public let sentences: [String]
            }
            public let expected: [Expected]
        }

        public struct ChaptersCase: Decodable, Sendable {
            public struct Summary: Decodable, Sendable {
                public let dayStart: Int64
                public let activeSeconds: Int
                public let topBundleId: String?
                public let topAppName: String?
                public let topSeconds: Int
            }
            public struct Expected: Decodable, Sendable {
                public struct App: Decodable, Sendable {
                    public let applicationName: String
                    public let days: Int
                    public let activeSeconds: Int
                }
                public let id: String
                public let startDay: Int64
                public let endDay: Int64
                public let category: String
                public let dayCount: Int
                public let totalActiveSeconds: Int
                public let apps: [App]
                public let representativeDay: Int64
                public let days: [Int64]
                public let defaultName: String
            }
            public let summaries: [Summary]
            public let expected: [Expected]
        }

        public struct RitualsCase: Decodable, Sendable {
            public struct App: Decodable, Sendable {
                public let applicationName: String
                public let bundleIdentifier: String?
                public let days: Int
            }
            public struct Slot: Decodable, Sendable {
                public let part: String
                public let applicationName: String
                public let days: Int
            }
            public struct Expected: Decodable, Sendable {
                public let slots: [Slot]
                public let firstApp: App?
            }
            public let events: [Fixture.Event]
            public let now: Int64
            public let expected: Expected
        }

        public struct AppStatsCase: Decodable, Sendable {
            public struct Expected: Decodable, Sendable {
                public let applicationName: String
                public let bundleIdentifier: String?
                public let totalSeconds: Int
                public let sessionCount: Int
                public let lastUsedAt: Int64
            }
            public let events: [Fixture.Event]
            public let now: Int64
            public let expected: [Expected]
        }

        public struct ResumeCase: Decodable, Sendable {
            public struct Input: Decodable, Sendable {
                public let name: String
                public let events: [Fixture.Event]
                public let now: Int64
            }
            public struct Target: Decodable, Sendable {
                public let sessionStart: Int64
                public let sessionTitle: String
                public let applicationName: String
                public let isEarlierDay: Bool
                public let when: String
            }
            public struct Expected: Decodable, Sendable {
                public let name: String
                public let target: Target?
            }
            public struct WhenCase: Decodable, Sendable {
                public let at: Int64
                public let now: Int64
                public let label: String
            }
            public let cases: [Input]
            public let expected: [Expected]
            public let whenCases: [WhenCase]
            public let dayLabels: [DayLabelCase]

            public struct DayLabelCase: Decodable, Sendable {
                public let at: Int64
                public let now: Int64
                public let relative: String
                public let short: String
            }
        }

        public struct WorkflowCase: Decodable, Sendable {
            public struct Expected: Decodable, Sendable {
                public struct App: Decodable, Sendable {
                    public let applicationName: String
                    public let bundleIdentifier: String?
                }
                public let id: String
                public let title: String
                public let category: String
                public let apps: [App]
                public let totalSeconds: Int
                public let sessionCount: Int
            }
            public let events: [Fixture.Event]
            public let now: Int64
            public let sessionCount: Int
            public let expected: [Expected]
            public let projects: [ProjectCase]

            public struct ProjectCase: Decodable, Sendable {
                public struct App: Decodable, Sendable {
                    public let applicationName: String
                    public let seconds: Int
                }
                public let id: String
                public let category: String
                public let apps: [App]
                public let totalSeconds: Int
                public let sessionCount: Int
                public let firstSeen: Int64
                public let lastActive: Int64
                public let sessionStarts: [Int64]
                public let defaultName: String
            }
        }

        public struct BreakCase: Decodable, Sendable {
            public let reason: String
            public let seconds: Int
            public let applicationName: String?
            public let title: String
            public let detail: String
        }
        public let timeZone: String
        public let locale: String
        public let exportedAtMillis: Int64
        public let grouping: Grouping
        /// What each kind of gap is called, straight from the reference's own
        /// `describeBreak`. Pure copy, and copy is where a port drifts silently.
        public let breaks: [BreakCase]
        /// A whole week, straight from the reference's `computeWeekSummary`.
        public let week: WeekCase
        /// Recurring application combinations, from the reference's `detectWorkflows`.
        public let workflows: WorkflowCase
        /// What to offer picking back up, and how a moment reads in words.
        public let resume: ResumeCase
        /// Per-application totals, from the reference's `computeAppStats`.
        public let appStats: AppStatsCase
        /// The shape a run of days settles into.
        public let rituals: RitualsCase
        /// Eras, read from the durable daily headlines.
        public let chapters: ChaptersCase
        /// The history told back, a period at a time.
        public let autobiography: AutobiographyCase
        /// The whole archive, at a glance.
        public let legacy: LegacyCase
        /// How two applications are used together.
        public let relationships: RelationshipsCase
        /// The memories worth rediscovering.
        public let moments: MomentsCase
        /// Contextual memory: the scoring, the selector, and the producers.
        public let memory: MemoryCase
        /// A quiet look back, before the day begins.
        public let briefings: BriefingCase
        /// The coarse buckets the Timeline filters by.
        public let filters: FilterCase

        public struct FilterCase: Decodable, Sendable {
            public struct Mapped: Decodable, Sendable {
                public let category: String
                public let bucket: String
            }
            public let categories: [String]
            public let mapped: [Mapped]
        }
        /// The graph behind the memory space.
        public let canvas: CanvasCase
        public let report: ReportCase
        public let search: SearchCase
        public let history: History
        public let collections: CollectionsCase
        public let stories: Stories
        public let scopes: Scopes
    }

    // ── results ───────────────────────────────────────────────────────────────

    /// One assertion, with enough context to be actionable on its own — these are read
    /// in a terminal as often as in a test report.
    public struct Check: Sendable {
        public let group: String
        public let what: String
        public let passed: Bool
        public let detail: String?
    }

    public struct Report: Sendable {
        public let glazeVersion: String
        public let glazeCommit: String
        public let specRoot: String
        public let checks: [Check]
        /// Fixture name → whether every check for it passed, in spec order.
        public let fixtureResults: [(name: String, description: String, passed: Bool)]

        public var failures: [Check] { checks.filter { !$0.passed } }
        public var passed: Bool { failures.isEmpty }
    }

    // ── locating spec/ ────────────────────────────────────────────────────────

    /// `spec/` sits beside the package rather than in the build products, so it is found
    /// relative to this source file unless a path is given (for CI).
    public static func defaultSpecRoot(file: String = #filePath) -> URL {
        var root = URL(fileURLWithPath: file)
        for _ in 0..<3 { root.deleteLastPathComponent() }   // Sources/ParityKit/ParityKit.swift
        return root.appendingPathComponent("spec")
    }

    static func load<T: Decodable>(_ type: T.Type, _ relative: String, from root: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: root.appendingPathComponent(relative)))
    }

    static func event(_ raw: Fixture.Event) -> ActivityEvent {
        ActivityEvent(
            id: raw.id,
            type: EventType(rawValue: raw.type) ?? .activated,
            applicationName: raw.applicationName,
            bundleIdentifier: raw.bundleIdentifier,
            appPath: raw.appPath,
            startedAt: raw.startedAt,
            endedAt: raw.endedAt,
            duration: raw.duration
        )
    }

    // ── the suite ─────────────────────────────────────────────────────────────

    public static func runAllChecks(specRoot: URL? = nil) throws -> Report {
        let root = specRoot ?? defaultSpecRoot()
        let constants = try load(Constants.self, "constants.json", from: root)
        let guideSpec = try load(GuideSpec.self, "guide.json", from: root)
        let settingsCopy = try load(SettingsCopySpec.self, "settings-copy.json", from: root)
        let narrative = try load(NarrativeCopySpec.self, "narrative-copy.json", from: root)

        var checks: [Check] = []
        func check(_ group: String, _ what: String, _ passed: Bool, _ detail: String? = nil) {
            checks.append(Check(group: group, what: what, passed: passed, detail: detail))
        }
        func equal<T: Equatable>(_ group: String, _ what: String, _ actual: T, _ expected: T) {
            checks.append(Check(
                group: group,
                what: what,
                passed: actual == expected,
                detail: actual == expected ? nil : "got \(actual), want \(expected)"
            ))
        }

        // constants — Rules in Model.swift is a second copy of these on purpose (the
        // shipping app should not parse JSON), so this is what keeps the copies equal.
        let g1 = "constants"
        equal(g1, "awayAfterSeconds", Rules.awayAfterSeconds, constants.tracker.awayAfterSeconds)
        equal(g1, "idlePollMs", Int(Rules.idlePollSeconds * 1000), constants.tracker.idlePollMs)
        equal(g1, "pointEventDedupeMs",
              Int(Rules.pointEventDedupeSeconds * 1000), constants.tracker.pointEventDedupeMs)
        equal(g1, "ignoredBundleIDs",
              Rules.ignoredBundleIDs.sorted(), constants.tracker.ignoredBundleIds.sorted())
        equal(g1, "idleStretchSeconds", Rules.idleStretchSeconds, constants.store.idleStretchSeconds)
        equal(g1, "compactMinFreeRatio", Rules.compactMinFreeRatio, constants.store.compactMinFreeRatio)
        equal(g1, "compactMinFreePages", Rules.compactMinFreePages, constants.store.compactMinFreePages)
        equal(g1, "deleteChunk", Rules.deleteChunk, constants.store.deleteChunk)
        equal(g1, "idleBreakSeconds", Rules.idleBreakSeconds, constants.derivation.idleBreakSeconds)
        equal(g1, "recordingGapSeconds",
              Rules.recordingGapSeconds, constants.derivation.recordingGapSeconds)
        equal(g1, "minSessionSeconds", Rules.minSessionSeconds, constants.derivation.minSessionSeconds)
        equal(g1, "maxTagLength", Rules.maxTagLength, constants.annotations.maxTagLength)
        equal(g1, "maxTags", Rules.maxTags, constants.annotations.maxTags)
        equal(g1, "how long a day takes to play back",
              Playback.baseDurationMillis, constants.playback.baseDurationMillis)
        equal(g1, "and the speeds offered", Playback.speeds, constants.playback.speeds)
        equal(g1, "focus goal presets", Goals.presetMinutes, constants.focusGoal.presetMinutes)
        equal(g1, "minCustomGoalMinutes", Goals.minCustomMinutes, constants.focusGoal.minCustomMinutes)
        equal(g1, "maxCustomGoalMinutes", Goals.maxCustomMinutes, constants.focusGoal.maxCustomMinutes)

        // motion — the design system's durations and curves, which are the reference's own.
        // A port that guesses 0.2s where the reference says 180ms is not visibly wrong in a
        // screenshot and is wrong every time anybody uses it.
        equal(g1, "press duration",
              Int((MotionTokens.pressSeconds * 1000).rounded()), constants.motion.pressMs)
        equal(g1, "hover duration",
              Int((MotionTokens.hoverSeconds * 1000).rounded()), constants.motion.hoverMs)
        equal(g1, "enter duration",
              Int((MotionTokens.enterSeconds * 1000).rounded()), constants.motion.enterMs)
        equal(g1, "the soft curve", MotionTokens.easeSoft, constants.motion.easeSoft)
        equal(g1, "the standard curve", MotionTokens.easeStandard, constants.motion.easeStandard)
        equal(g1, "stagger step",
              Int((MotionTokens.staggerSeconds * 1000).rounded()), constants.motion.enterStepMs)
        equal(g1, "stagger cap",
              Int((MotionTokens.staggerCapSeconds * 1000).rounded()), constants.motion.enterCapMs)
        equal(g1, "a search result's own stagger",
              Int((MotionTokens.resultStaggerSeconds * 1000).rounded()),
              constants.search.resultStepMs)
        equal(g1, "and its cap",
              Int((MotionTokens.resultStaggerCapSeconds * 1000).rounded()),
              constants.search.resultCapMs)

        // search and the Timeline's ranges. Both surfaces were audited and neither had its
        // behaviour wrong — what they had was constants and copy that nothing held. The
        // subtitles below are the reason this matters most: they are words a person reads,
        // and the words are the product (SPEC §8).
        equal(g1, "how far back Search looks", ReplayCore.Report.fetchDays, constants.search.days)
        equal(
            g1, "how many sessions a concept answers with",
            Search.conceptLimit, constants.search.conceptLimit
        )
        equal(
            g1, "the search spans offered",
            Search.Span.allCases.map(\.rawValue), constants.search.spans.map(\.value)
        )
        equal(
            g1, "and what they are called",
            Search.Span.allCases.map(\.label), constants.search.spans.map(\.label)
        )
        equal(
            g1, "the Timeline's ranges, in order",
            TimeRange.allCases.map(\.rawValue), constants.timeline.order.map {
                // The reference names its two multi-day ranges by length; this port names
                // them by period. The mapping is the only thing about them that differs.
                switch $0 {
                case "7d": "week"
                case "30d": "month"
                default: $0
                }
            }
        )
        equal(
            g1, "what the Timeline opens on",
            defaultTimeRange.days, constants.timeline.ranges
                .first { $0.key == constants.timeline.defaultRange }?.days ?? -1
        )
        for (range, expected) in zip(TimeRange.allCases, constants.timeline.ranges) {
            equal(g1, "\(expected.key): days fetched", range.days, expected.days)
            equal(g1, "\(expected.key): its name", range.label, expected.label)
            equal(g1, "\(expected.key): the line under the title", range.subtitle, expected.subtitle)
            // Upstream keeps a day by its *label*; this port keeps it by an offset back from
            // today, which is the same rule expressed against a calendar rather than a
            // string. What is compared is whether one day is kept or all of them.
            equal(
                g1, "\(expected.key): one day kept or all",
                range.keepDayOffset != nil, expected.keepDayLabels != nil
            )
        }

        // the canvas camera — the same argument as the motion tokens above, for a surface
        // that had nothing holding it. A field you cannot push as far out, that jumps a
        // third further on each press of zoom, and that stops dead when you let go of a
        // flick is a different instrument to play, and every one of those was true here.
        // Today's reflection prompt, which is words a person reads and so is the product.
        equal(
            g1, "the hour the reflection prompt turns",
            ReflectionPrompt.eveningFromHour, constants.today.eveningFromHour
        )
        equal(g1, "what Today asks before then", ReflectionPrompt.daytime, constants.today.prompt)
        equal(
            g1, "and what it asks once the day is ending",
            ReflectionPrompt.evening, constants.today.eveningPrompt
        )

        // Apps' three windows — the same copy-with-no-contract the Timeline's ranges were,
        // on the parallel type that was missed when those were brought in.
        equal(
            g1, "the windows Apps offers",
            AppWindow.allCases.map(\.rawValue), constants.apps.windows.map(\.value)
        )
        for (window, expected) in zip(AppWindow.allCases, constants.apps.windows) {
            equal(g1, "\(expected.value): its name", window.label, expected.label)
            equal(g1, "\(expected.value): days back", window.days, expected.days)
            equal(g1, "\(expected.value): the line under the title", window.subtitle, expected.subtitle)
        }

        // What This Week holds itself to.
        equal(
            g1, "how many applications the week lists",
            WeekSummary.appLimit, constants.week.appLimit
        )
        equal(
            g1, "how many recurring combinations it shows",
            WeekSummary.workflowLimit, constants.week.workflowLimit
        )
        equal(g1, "the hours the day-arc is marked at", WeekSummary.arcTicks, constants.week.arcTicks)

        equal(
            g1, "how far back a single day can be deleted from Settings",
            deletableDaysWindow, constants.deletion.deletableDaysWindow
        )
        equal(
            g1, "the Dock badge's unit",
            DockBadgeLabel.hourSeconds, constants.dockBadge.hourSeconds
        )
        equal(
            g1, "how long before the Dock badge appears",
            DockBadgeLabel.minimumHours, constants.dockBadge.minimumHours
        )

        // Settings row names. Only the rows this port has — the contract carries all of the
        // reference's, and the difference is the backlog rather than a failure.
        let referenceLabels = Set(settingsCopy.rows.map(\.label))
        let referenceCopy = Dictionary(
            settingsCopy.rows.map { ($0.label, $0.description) }, uniquingKeysWith: { a, _ in a }
        )
        for row in SettingsRow.allCases {
            // `base`, not `label`: the label is what a reader sees and is translated, and this
            // compares against the reference's English. On a translated machine the two would
            // otherwise disagree for a reason that has nothing to do with the port drifting.
            equal(g1, "Settings row: \(row.rawValue)", referenceLabels.contains(row.base), true)
            // The line under it, where the reference writes one. This is the half a person
            // reads when they are unsure what a switch does, which is the only time they read
            // Settings at all.
            equal(
                g1, "Settings copy: \(row.rawValue)",
                row.explanation, referenceCopy[row.base] ?? nil
            )
        }

        // And the rows that are this port's own, checked the other way round: they must
        // *not* exist upstream. A name collision would mean two settings called the same
        // thing meaning different things, which is the failure this list exists to prevent.
        for row in OwnSettingsRow.allCases {
            equal(
                g1, "own Settings row is not the reference's: \(row.rawValue)",
                referenceLabels.contains(row.base), false
            )
            equal(
                g1, "own Settings row explains itself: \(row.rawValue)",
                row.explanation.isEmpty, false
            )
        }

        // The Guide, word for word. Sixteen answers a person reads, which SPEC §8 calls the
        // product — and the place a paraphrase would be least visible and most costly, since
        // nobody re-reads a help page against its source.
        equal(g1, "how many questions the Guide answers", Guide.entries.count, guideSpec.entries.count)
        for (mine, expected) in zip(Guide.entries, guideSpec.entries) {
            equal(g1, "Guide: \(expected.question)", mine.question, expected.question)
            equal(g1, "Guide answer: \(expected.question)", mine.answer, expected.answer)
        }

        // And the Guide entries that are this port's own, the other way round again: their
        // questions must not exist upstream. Both exist because this port answers something
        // the reference's own answer cannot — it updates through the Glaze Store, and its
        // idle timer raises only the screensaver — so the reference's flat "no network" and
        // its screensaver answer each need a footnote beside them rather than an edit inside
        // them. See `Guide.ownEntries`.
        let referenceQuestions = Set(guideSpec.entries.map(\.question))
        for entry in Guide.ownEntries {
            equal(
                g1, "own Guide question is not the reference's: \(entry.question)",
                referenceQuestions.contains(entry.question), false
            )
            equal(
                g1, "own Guide question is answered: \(entry.question)",
                entry.answer.isEmpty, false
            )
        }

        // Living Home: what Today leads with, and how it is chosen.
        equal(
            g1, "how fresh a resume target has to be to lead",
            Int(todayHeroRecentSeconds / 3600), constants.today.heroRecentHours
        )
        equal(
            g1, "how far back Today looks for a reflection",
            todayHeroReflectionLookbackDays, constants.today.reflectionLookbackDays
        )
        equal(
            g1, "the order the heroes rotate in",
            TodayHero.allCases.map(\.rawValue), constants.today.heroOrder
        )

        // The narrative surfaces' prose, character for character.
        let gN = "narrative copy"
        equal(gN, "Story's title", NarrativeCopy.storyTitle, narrative.story.title)
        equal(gN, "Story's subtitle", NarrativeCopy.storySubtitle, narrative.story.subtitle)
        equal(
            gN, "the hub has four ways in",
            NarrativeCopy.storyHub.count, narrative.story.hub.count
        )
        for (ours, theirs) in zip(NarrativeCopy.storyHub, narrative.story.hub) {
            equal(gN, "the hub card \"\(theirs.title)\"", ours.title, theirs.title)
            equal(gN, "what \"\(theirs.title)\" says it is", ours.detail, theirs.detail)
        }
        equal(gN, "the rituals label", NarrativeCopy.ritualsLabel, narrative.story.ritualsLabel)
        equal(
            gN, "how a ritual is explained",
            NarrativeCopy.ritualsFootnote, narrative.story.ritualsFootnote
        )
        equal(
            gN, "what an empty rituals section is called",
            NarrativeCopy.ritualsEmptyTitle, narrative.story.ritualsEmptyTitle
        )
        equal(
            gN, "and what it says",
            NarrativeCopy.ritualsEmptyDetail, narrative.story.ritualsEmptyDetail
        )
        equal(
            gN, "Chapters' subtitle",
            NarrativeCopy.chaptersSubtitle, narrative.chapters.subtitle
        )
        equal(
            gN, "Chapters with nothing in it",
            NarrativeCopy.chaptersEmptyTitle, narrative.chapters.emptyTitle
        )
        equal(
            gN, "and what that explains",
            NarrativeCopy.chaptersEmptyDetail, narrative.chapters.emptyDetail
        )
        equal(
            gN, "Autobiography's subtitle",
            NarrativeCopy.autobiographySubtitle, narrative.autobiography.subtitle
        )
        equal(
            gN, "Autobiography with nothing in it",
            NarrativeCopy.autobiographyEmptyTitle, narrative.autobiography.emptyTitle
        )
        equal(
            gN, "and what that explains",
            NarrativeCopy.autobiographyEmptyDetail, narrative.autobiography.emptyDetail
        )
        equal(
            gN, "where every sentence comes from",
            NarrativeCopy.autobiographyFootnote, narrative.autobiography.footnote
        )

        equal(gN, "Museum's subtitle", NarrativeCopy.museumSubtitle, narrative.museum.subtitle)
        equal(
            gN, "the museum's five rooms",
            NarrativeCopy.museumSections, narrative.museum.sections
        )
        equal(
            gN, "a museum with nothing in it",
            NarrativeCopy.museumEmptyTitle, narrative.museum.emptyTitle
        )
        equal(
            gN, "and what will fill it",
            NarrativeCopy.museumEmptyDetail, narrative.museum.emptyDetail
        )
        equal(gN, "My Story's subtitle", NarrativeCopy.legacySubtitle, narrative.legacy.subtitle)
        equal(
            gN, "My Story's three sections",
            NarrativeCopy.legacySections, narrative.legacy.sections
        )
        equal(
            gN, "My Story before there is one",
            NarrativeCopy.legacyEmptyTitle, narrative.legacy.emptyTitle
        )
        equal(
            gN, "and what it will become",
            NarrativeCopy.legacyEmptyDetail, narrative.legacy.emptyDetail
        )
        equal(
            gN, "an application with no recent history",
            NarrativeCopy.appHistoryEmptyTitle, narrative.appHistory.emptyTitle
        )
        equal(
            gN, "and the window that explains it",
            NarrativeCopy.appHistoryEmptyDetail, narrative.appHistory.emptyDetail
        )
        equal(
            gN, "two applications that never met",
            NarrativeCopy.relationshipEmptyTitle, narrative.relationship.emptyTitle
        )
        equal(
            gN, "and the window that explains that",
            NarrativeCopy.relationshipEmptyDetail, narrative.relationship.emptyDetail
        )

        // The menu bar, which nobody had audited — the list of surfaces was built from the
        // reference's router, and a status item has no route.
        let t = constants.tray
        equal(g1, "how many recent applications it names", MenuBar.recentLimit, t.recentLimit)
        equal(g1, "how far back it looks for them", MenuBar.recentHours, t.recentHours)
        // The glyph is checked because it is a decision with a reason, not decoration: in
        // the menu bar `clock.arrow.circlepath` is Time Machine's, which this port used.
        equal(g1, "the status item's glyph", MenuBar.symbol, t.symbol)
        equal(g1, "what it says when paused", MenuBar.pausedLabel, t.paused)
        equal(g1, "and when you are away", MenuBar.awayLabel, t.away)
        equal(g1, "and when nothing has come through yet", MenuBar.waitingLabel, t.waiting)
        equal(g1, "the recent section's heading", MenuBar.recentHeading, t.recentHeading)
        equal(
            g1, "how a current session is described",
            MenuBar.focusedFor(600).hasPrefix(t.focusedFor), true
        )
        equal(g1, "under a minute reads as", MenuBar.shortDuration(20), t.justNow)
        equal(
            g1, "the tooltip when paused",
            MenuBar.tooltip(isRecording: false, current: nil), t.tooltipPaused
        )
        equal(
            g1, "and when tracking with nothing in front",
            MenuBar.tooltip(isRecording: true, current: nil), t.tooltipTracking
        )
        // The four states, and the order they are tested in — paused beats away, away beats
        // whatever the tracker last saw. The other order names an application you walked
        // away from as the thing you are doing.
        equal(
            g1, "paused wins over everything",
            MenuBar.now(isRecording: false, isAway: true, current: ("Xcode", 0), now: 0), .paused
        )
        equal(
            g1, "away wins over a stale current",
            MenuBar.now(isRecording: true, isAway: true, current: ("Xcode", 0), now: 0), .away
        )
        equal(
            g1, "nothing in front is waiting, not idle",
            MenuBar.now(isRecording: true, isAway: false, current: nil, now: 0), .waiting
        )
        equal(
            g1, "and otherwise it is the application, with its elapsed time",
            MenuBar.now(
                isRecording: true, isAway: false, current: ("Xcode", 0), now: 600_000
            ),
            .inApplication(name: "Xcode", seconds: 600)
        )

        // A week begins on Monday, everywhere in the app.
        //
        // The reference settles this in `startOfWeek` — `(d.getDay() + 6) % 7`, "days since
        // Monday" — and it is not the locale's answer: en-US says Sunday. It lived privately
        // in `Autobiography` until the heatmap needed one and reached for `firstWeekday`
        // instead, so the grid drew a week the rest of the app did not recognise. Checked
        // across all seven weekdays, in whatever calendar the suite is running under.
        // **Derived, not asserted.** The first version of this pinned a fixed instant and
        // called it "a Monday" — which it is in UTC+5, where it was written, and is not in
        // UTC, where it is a Sunday. All seven checks failed on every CI runner for six
        // hours. The four-timezone matrix exists for exactly this and caught it immediately;
        // nobody looked. Twice now this project has been bitten by a *local* truth written
        // into a test (see docs/FINDINGS.md), and both times it was invisible at the desk.
        //
        // So: take any instant, ask what week it is in, and check that all seven of that
        // week's days agree — which holds wherever it runs. Then check separately that the
        // week began on a Monday, which is the claim being made.
        let weekCalendar = Calendar.current
        let mondayProbe = startOfWeek(1_785_092_400_000)
        let mondayDate = Date(timeIntervalSince1970: Double(mondayProbe) / 1000)
        equal(
            g1, "a week begins on a Monday",
            weekCalendar.component(.weekday, from: mondayDate), 2
        )
        for offset in 0..<7 {
            // Calendar arithmetic rather than adding milliseconds: a day is not always
            // 86,400,000ms, and a week that crosses a daylight-saving boundary would
            // otherwise land this probe on the wrong side of midnight.
            guard let day = weekCalendar.date(byAdding: .day, value: offset, to: mondayDate)
            else { continue }
            let millis = Int64((day.timeIntervalSince1970 * 1000).rounded())
            equal(
                g1, "day \(offset) of that week resolves to the same Monday",
                startOfWeek(millis), mondayProbe
            )
        }

        // The screensaver's marquee. Its reduced-motion answer is the interesting half:
        // the reference slows it rather than stopping it, because a surface whose whole
        // content is movement has nothing left if the movement goes.
        equal(
            g1, "how long one pass of the drift takes",
            Int(ScreensaverTokens.driftSeconds), constants.screensaver.driftSeconds
        )
        equal(
            g1, "and how long with motion reduced",
            Int(ScreensaverTokens.reducedSeconds), constants.screensaver.reducedSeconds
        )

        equal(
            g1, "how long one ambient breath takes",
            Int(ScreensaverTokens.breatheSeconds), constants.screensaver.breatheSeconds
        )
        equal(
            g1, "how far it swells",
            ScreensaverTokens.breatheScale, constants.screensaver.breatheScale
        )
        equal(
            g1, "and how far it fades between",
            ScreensaverTokens.breatheFloor, constants.screensaver.breatheFloor
        )

        // The heatmap's steps. Shading against fixed amounts rather than against the busiest
        // day in the window is the whole claim the grid makes, so the boundaries are checked
        // from both sides — a second under a threshold and a second over it.
        let h = constants.heatmap
        equal(g1, "the step half an hour reaches", Heatmap.lowSeconds, h.lowSeconds)
        equal(g1, "the step an hour and a half reaches", Heatmap.midSeconds, h.midSeconds)
        equal(g1, "the step three hours reaches", Heatmap.highSeconds, h.highSeconds)
        equal(g1, "how much accent each step mixes in", Heatmap.levelMix, h.levelMix)
        equal(g1, "an empty day is empty", Heatmap.level(0).rawValue, 0)
        equal(g1, "a second of activity is not", Heatmap.level(1).rawValue, 1)
        equal(g1, "a second under half an hour", Heatmap.level(h.lowSeconds - 1).rawValue, 1)
        equal(g1, "half an hour exactly", Heatmap.level(h.lowSeconds).rawValue, 2)
        equal(g1, "a second under an hour and a half", Heatmap.level(h.midSeconds - 1).rawValue, 2)
        equal(g1, "an hour and a half exactly", Heatmap.level(h.midSeconds).rawValue, 3)
        equal(g1, "a second under three hours", Heatmap.level(h.highSeconds - 1).rawValue, 3)
        equal(g1, "three hours exactly", Heatmap.level(h.highSeconds).rawValue, 4)
        equal(g1, "how far the week range reaches", Heatmap.Range.week.backDays, h.weekBackDays)
        equal(g1, "how far the month range reaches", Heatmap.Range.month.backDays, h.monthBackDays)
        equal(g1, "how far the year range reaches", Heatmap.Range.year.backDays, h.yearBackDays)
        equal(g1, "how many week-columns a year draws", Heatmap.yearWeeks, h.yearWeeks)
        equal(g1, "how many cells a month draws", Heatmap.monthCells, h.monthCells)
        equal(
            g1, "how early a month has to start to be labelled",
            Heatmap.monthLabelMaxDate, h.monthLabelMaxDate
        )

        let c = CanvasTokens.self
        equal(g1, "how long the tour rests on a stop",
              Int((c.tourDwellSeconds * 1000).rounded()), constants.canvas.tourDwellMillis)
        equal(g1, "how many neighbours the tour visits",
              c.tourNeighbours, constants.canvas.tourNeighbours)
        equal(g1, "how long the tour's camera takes",
              Int((c.tourCameraSeconds * 1000).rounded()), constants.canvas.tourCameraMillis)
        equal(g1, "the tour's zoom at either end", c.tourEndZoom, constants.canvas.tourEndZoom)
        equal(g1, "and in the middle", c.tourStepZoom, constants.canvas.tourStepZoom)
        equal(g1, "the zoom a focused node is brought to",
              c.focusZoom, constants.canvas.focusZoom)
        equal(g1, "the zoom centring settles on", c.centreZoom, constants.canvas.centreZoom)
        equal(g1, "how long centring takes",
              Int((c.centreSeconds * 1000).rounded()), constants.canvas.centreMillis)
        equal(g1, "the camera's own flight time",
              Int((c.cameraSeconds * 1000).rounded()), constants.canvas.cameraMillis)
        equal(g1, "one press of zoom", c.zoomButtonStep, constants.canvas.zoomButtonStep)
        equal(g1, "how long a press of zoom takes",
              Int((c.zoomButtonSeconds * 1000).rounded()), constants.canvas.zoomButtonMillis)
        equal(
            g1, "how far back an unconnected node falls",
            c.unfocusedOpacity, constants.canvas.unfocusedOpacity
        )
        equal(
            g1, "the zoom applications start fading at",
            c.appsFadedBelowZoom, constants.canvas.appsFadedBelowZoom
        )
        equal(g1, "how faint a faded application is", c.appFaded, constants.canvas.appFadedOpacity)
        equal(
            g1, "the zoom an application's name appears at",
            c.appLabelsFromZoom, constants.canvas.appLabelsFromZoom
        )
        equal(g1, "how far out the field goes", c.minZoom, constants.canvas.minZoom)
        equal(g1, "and how far in", c.maxZoom, constants.canvas.maxZoom)
        equal(g1, "one notch of an ordinary wheel", c.wheelStep, constants.canvas.wheelStep)
        equal(g1, "how hard a pinch zooms",
              c.wheelSensitivity, constants.canvas.wheelSensitivity)
        equal(g1, "the speed a flick has to beat to glide",
              c.glideMinSpeed, constants.canvas.glideMinSpeed)
        equal(g1, "what a glide keeps each frame", c.glideDecay, constants.canvas.glideDecay)
        equal(g1, "the speed a glide is called finished at",
              c.glideRestSpeed, constants.canvas.glideRestSpeed)

        // the category table — order-sensitive, because first match wins and it names
        // the session.
        let g2 = "category table"
        for entry in constants.derivation.categoryPatterns {
            let probe = entry.pattern
                .split(separator: "|").first
                .map {
                    String($0)
                        .replacingOccurrences(of: "^", with: "")
                        .replacingOccurrences(of: "$", with: "")
                } ?? ""
            guard !probe.isEmpty else { continue }
            equal(g2, "categorizeApp(\"\(probe)\")", categorizeApp(probe).rawValue, entry.category)
        }

        // schema — a database written by either implementation must be readable by the
        // other, so this is compared statement for statement.
        let generatedSchema = try String(
            contentsOf: root.appendingPathComponent("schema.sql"),
            encoding: .utf8
        )
        func normalise(_ sql: String) -> String {
            sql.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("--") }
                .joined(separator: " ")
        }
        equal("schema", "ActivityStore.schema matches spec/schema.sql",
              normalise(ActivityStore.schemaForParityCheck), normalise(generatedSchema))

        // session derivation — against the output the Glaze code actually produced.
        struct Index: Decodable { let fixtures: [String] }
        let index = try load(Index.self, "fixtures/index.json", from: root)
        var fixtureResults: [(name: String, description: String, passed: Bool)] = []

        for name in index.fixtures {
            let fixture = try load(Fixture.self, "fixtures/\(name).json", from: root)
            let before = checks.count
            // Derived in the timezone the fixture was generated under, not the machine's.
            // Session titles are named after the local day part, so without this the suite
            // passes here and fails in CI — the fixture would be recording where it was made.
            var fixtureCalendar = Calendar(identifier: .gregorian)
            fixtureCalendar.timeZone = TimeZone(identifier: fixture.timeZone) ?? .gmt
            let produced = buildTimeline(
                fixture.events.map(event), now: fixture.now, calendar: fixtureCalendar
            )
            let group = "derivation/\(name)"

            equal(group, "number of items", produced.count, fixture.expected.count)
            if produced.count == fixture.expected.count {
                for (offset, expected) in fixture.expected.enumerated() {
                    switch produced[offset] {
                    case .session(let session):
                        equal(group, "[\(offset)] kind", "session", expected.kind)
                        equal(group, "[\(offset)] title", session.title, expected.title ?? "")
                        equal(group, "[\(offset)] category",
                              session.category.rawValue, expected.category ?? "")
                        equal(group, "[\(offset)] startedAt", session.startedAt, expected.startedAt)
                        equal(group, "[\(offset)] endedAt", session.endedAt, expected.endedAt)
                        equal(group, "[\(offset)] spanSeconds",
                              session.spanSeconds, expected.spanSeconds ?? -1)
                        equal(group, "[\(offset)] activeSeconds",
                              session.activeSeconds, expected.activeSeconds ?? -1)
                        equal(group, "[\(offset)] switches", session.switches, expected.switches ?? -1)
                        equal(group, "[\(offset)] rows the session is made of",
                              session.events.map(\.id), expected.eventIds ?? [])
                        equal(group, "[\(offset)] app order",
                              session.apps.map(\.applicationName),
                              (expected.apps ?? []).map(\.applicationName))
                        for (app, expectedApp) in zip(session.apps, expected.apps ?? []) {
                            equal(group, "\(app.applicationName) seconds",
                                  app.seconds, expectedApp.seconds)
                            equal(group, "\(app.applicationName) switches",
                                  app.switches, expectedApp.switches)
                            check(group, "\(app.applicationName) share",
                                  abs(app.share - expectedApp.share) < 0.000_01,
                                  "got \(app.share), want \(expectedApp.share)")
                        }

                    case .breakItem(let gap):
                        equal(group, "[\(offset)] kind", "break", expected.kind)
                        equal(group, "[\(offset)] reason", gap.reason.rawValue, expected.reason ?? "")
                        equal(group, "[\(offset)] startedAt", gap.startedAt, expected.startedAt)
                        equal(group, "[\(offset)] endedAt", gap.endedAt, expected.endedAt)
                        equal(group, "[\(offset)] seconds", gap.seconds, expected.seconds ?? -1)
                        equal(group, "[\(offset)] applicationName",
                              gap.applicationName, expected.applicationName)
                    }
                }
            }
            // The day's headline, from the same rows.
            let events = fixture.events.map(event)
            let summary = computeDaySummary(
                events: events, timeline: produced,
                dayStart: startOfLocalDay(fixture.events.first?.startedAt ?? fixture.now),
                now: fixture.now
            )
            let sg = "summary/\(name)"
            equal(sg, "activeSeconds", summary.activeSeconds, fixture.summary.activeSeconds)
            equal(sg, "activeLabel", formatDurationShort(summary.activeSeconds), fixture.summary.activeLabel)
            equal(sg, "appsUsed", summary.appsUsed, fixture.summary.appsUsed)
            equal(sg, "sessionCount", summary.sessionCount, fixture.summary.sessionCount)
            equal(sg, "switches", summary.switches, fixture.summary.switches)
            equal(sg, "focus stretch", summary.focus?.averageStretchSeconds,
                  fixture.summary.focus?.averageStretchSeconds)
            equal(sg, "focus quality", summary.focus?.quality.rawValue, fixture.summary.focus?.quality)
            equal(sg, "top app", summary.mostUsed?.applicationName, fixture.summary.mostUsed?.applicationName)
            equal(sg, "top app seconds", summary.mostUsed?.seconds, fixture.summary.mostUsed?.seconds)
            equal(sg, "longest session", summary.longestSession?.activeSeconds,
                  fixture.summary.longestSessionSeconds)

            let stillPassing = checks[before...].allSatisfy(\.passed)
            fixtureResults.append((name, fixture.description, stillPassing))
        }

        // the store, end to end against a real SQLite file.
        let group = "store round-trip"
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-parity-\(UUID().uuidString).db")
        let store = ActivityStore(path: tmp.path)
        try store.open()
        let t0 = Int64(1_770_000_000_000)
        let id = try store.openSession(
            name: "Code", bundleID: "com.microsoft.VSCode", appPath: nil, startedAt: t0
        )
        try store.closeSession(id: id, endedAt: t0 + 600_000)
        try store.recordAway(startedAt: t0 + 600_000, endedAt: t0 + 1_200_000)
        equal(group, "two rows written", try store.countRows(), 2)
        let read = try store.sessions(
            from: startOfLocalDay(t0), to: startOfLocalDay(t0) + dayMillis
        )
        equal(group, "both rows read back", read.count, 2)
        equal(group, "duration computed by SQL, in seconds", read.first?.duration, 600)
        equal(group, "a fresh database has nothing to reclaim", try store.reclaimableBytes(), 0)
        check(group, "integrity check passes", store.integrityCheck().ok)
        // annotations, against the same file. These have no generated fixture — the sync
        // tool emits the two caps and the schema, not scenarios — so what is checked is the
        // behaviour the reference's `AnnotationsStore` documents in prose: keyed by session
        // start, merged on write, and deleted rather than kept blank.
        let ag = "annotations"
        let sessionStart = t0
        equal(ag, "an unannotated session reads back empty",
              try store.annotation(sessionStart: sessionStart), SessionAnnotation(sessionStart: sessionStart))

        _ = try store.setNote(sessionStart: sessionStart, note: "shipped the timeline", now: t0)
        _ = try store.setBookmarked(sessionStart: sessionStart, bookmarked: true, now: t0)
        // Normalisation is the part a port gets wrong: case, a leading #, blanks, and
        // duplicates all have to collapse, or one tag becomes two.
        _ = try store.setTags(
            sessionStart: sessionStart,
            tags: ["#Deep Work", "deep work", "  ", "Shipping", String(repeating: "x", count: 40)],
            now: t0
        )
        let stored = try store.annotation(sessionStart: sessionStart)
        equal(ag, "the note survives", stored.note, "shipped the timeline")
        equal(ag, "the bookmark survives a later write", stored.bookmarked, true)
        equal(ag, "tags normalise, dedupe and drop blanks",
              stored.tags, ["deep work", "shipping", String(repeating: "x", count: Rules.maxTagLength)])
        equal(ag, "a tag is capped at maxTagLength", stored.tags.last?.count, Rules.maxTagLength)
        equal(ag, "tags are capped at maxTags",
              try store.setTags(
                  sessionStart: sessionStart,
                  tags: (0..<(Rules.maxTags + 5)).map { "tag\($0)" },
                  now: t0
              ).tags.count,
              Rules.maxTags)

        equal(ag, "a range query finds it",
              try store.annotations(from: sessionStart, to: sessionStart + 1).count, 1)
        equal(ag, "a range that excludes its start does not",
              try store.annotations(from: sessionStart + 1, to: sessionStart + 2).count, 0)
        equal(ag, "bookmarks are listed", try store.bookmarkedAnnotations().count, 1)
        equal(ag, "allTags reports what is in use", try store.allTags().count, Rules.maxTags)

        // Cleared back to empty, the row goes rather than lingering as a blank.
        _ = try store.setBookmarked(sessionStart: sessionStart, bookmarked: false, now: t0)
        _ = try store.setTags(sessionStart: sessionStart, tags: [], now: t0)
        let emptied = try store.setNote(sessionStart: sessionStart, note: "   ", now: t0)
        equal(ag, "an emptied annotation reports no updatedAt", emptied.updatedAt, 0)
        equal(ag, "and leaves no row behind",
              try store.annotations(from: sessionStart, to: sessionStart + 1).count, 0)

        // Orphan pruning is by reachability: an annotation is live exactly while some
        // event still starts at that instant.
        _ = try store.setBookmarked(sessionStart: sessionStart, bookmarked: true, now: t0)
        equal(ag, "an annotation on a live session is kept", try store.pruneOrphanAnnotations(), 0)
        _ = try store.setBookmarked(sessionStart: t0 - 1, bookmarked: true, now: t0)
        equal(ag, "one pointing at no event is pruned", try store.pruneOrphanAnnotations(), 1)

        let deleted = try store.deleteEvents(ids: [id])
        equal(group, "delete by id removes one row", deleted.removed, 1)
        equal(group, "and reports the day it fell on", deleted.dayStarts, [startOfLocalDay(t0)])
        equal(ag, "deleting the session orphans its annotation",
              try store.pruneOrphanAnnotations(), 1)

        // maintenance — the operations Settings runs. The compaction sequence is SPEC §7,
        // where the order *is* the safety: copy, vacuum, verify by integrity check **and**
        // row count, and only then remove the copy.
        let mg = "maintenance"
        let excludable = try store.openSession(
            name: "Sublime Text", bundleID: "com.sublimetext.4", appPath: nil, startedAt: t0
        )
        try store.closeSession(id: excludable, endedAt: t0 + 60_000)
        equal(mg, "known apps are read from the events themselves",
              try store.listKnownApps().map(\.bundleIdentifier), ["com.sublimetext.4"])

        let rowsBefore = try store.countRows()
        let copyPath = URL(fileURLWithPath: tmp.path).deletingLastPathComponent()
            .appendingPathComponent("activity-before-compaction.db").path
        let compaction = try store.compactSafely()
        equal(mg, "compaction verifies the row count survived", compaction.rows, rowsBefore)
        check(mg, "it reports no surviving copy when it verified", compaction.backupPath == nil)
        check(mg, "and the copy it took is gone from disk",
              !FileManager.default.fileExists(atPath: copyPath))
        check(mg, "the database still passes its integrity check", store.integrityCheck().ok)
        equal(mg, "and still holds every row", try store.countRows(), rowsBefore)

        // Excluding an app erases what it recorded — past as well as future.
        equal(mg, "excluding nothing deletes nothing", try store.deleteByBundleIDs([]), 0)
        equal(mg, "excluding an app deletes its rows",
              try store.deleteByBundleIDs(["com.sublimetext.4"]), 1)
        equal(mg, "and leaves the rest alone", try store.countRows(), rowsBefore - 1)

        // reflections — the same empty-row rule annotations follow.
        let rg = "reflections"
        let day = startOfLocalDay(t0)
        equal(rg, "a day with nothing written reads back empty",
              try store.reflection(dayStart: day), Reflection(dayStart: day))
        _ = try store.setReflection(dayStart: day, text: "  a good day  ", now: t0)
        let written = try store.reflection(dayStart: day)
        equal(rg, "the text is stored as written, not trimmed", written.text, "  a good day  ")
        equal(rg, "and carries when it was written", written.updatedAt, t0)
        equal(rg, "a range finds it", try store.reflections(from: day, to: day + dayMillis).count, 1)
        _ = try store.setReflection(dayStart: day, text: "   ", now: t0)
        equal(rg, "cleared back to blank, it leaves no row",
              try store.reflections(from: day, to: day + dayMillis).count, 0)

        /// Compare multi-line text and, on a mismatch, name the first line that differs.
        ///
        /// A whole report echoed into a terminal is not a diagnosis; the line number and the
        /// two versions of that one line are.
        func equalText(_ group: String, _ what: String, _ actual: String, _ expected: String) {
            if actual == expected {
                checks.append(Check(group: group, what: what, passed: true, detail: nil))
                return
            }
            let ours = actual.components(separatedBy: "\n")
            let theirs = expected.components(separatedBy: "\n")
            var detail = "differs in length only (\(ours.count) lines vs \(theirs.count))"
            for index in 0..<max(ours.count, theirs.count) {
                let a = index < ours.count ? ours[index] : "<no line>"
                let b = index < theirs.count ? theirs[index] : "<no line>"
                if a != b {
                    detail = "line \(index + 1):\n        ours: \(a)\n        spec: \(b)"
                    break
                }
            }
            checks.append(Check(group: group, what: what, passed: false, detail: detail))
        }

        /// Fold the non-breaking space variants onto a plain space.
        ///
        /// Foundation and Node bundle different ICU versions, and the newer one separates a
        /// time from its meridiem with a narrow no-break space (U+202F) where the older uses
        /// U+0020 — so "2:40:00 AM" and "2:40:00 AM" differ by a byte neither implementation
        /// chose. Pinning that byte would make the suite fail on an OS or Node upgrade for a
        /// reason no reader of the file could see. Only the space class is folded; every
        /// other character still has to match exactly.
        func withPlainSpaces(_ text: String) -> String {
            text
                .replacingOccurrences(of: "\u{202F}", with: " ")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
        }

        // Day grouping and report text, against output the reference actually produced.
        // Both used to be "verified by reading the reference", which is the weakest kind of
        // verification here — these replace it.
        let fixture = try load(GroupingAndExport.self, "grouping-and-export.json", from: root)
        let environment = ReplayCore.Report.Environment(
            locale: Locale(identifier: fixture.locale),
            timeZone: TimeZone(identifier: fixture.timeZone) ?? .gmt
        )
        // Grouping buckets by *local* midnight, so it is checked in the timezone the
        // fixture was generated under — otherwise this measures the machine, not the code.
        let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = environment.timeZone
            return calendar
        }()

        let dg = "day grouping"
        let grouped = groupByDay(fixture.grouping.events.map(event), calendar: calendar)
        equal(dg, "the same days, newest first",
              grouped.map(\.dayStart), fixture.grouping.expected.map(\.dayStart))
        equal(dg, "with the same rows in each, oldest first within a day",
              grouped.map { $0.events.map(\.id) }, fixture.grouping.expected.map(\.eventIds))
        check(dg, "a run before midnight lands on the day it began, not the day it reached",
              grouped.last?.events.map(\.id) == [1])

        let bg = "break copy"
        for expected in fixture.breaks {
            guard let reason = BreakReason(rawValue: expected.reason) else {
                check(bg, "the port knows the reason '\(expected.reason)'", false)
                continue
            }
            let described = describeBreak(ActivityBreak(
                reason: reason, startedAt: 0, endedAt: 0, seconds: expected.seconds,
                applicationName: expected.applicationName
            ))
            let named = expected.applicationName.map { " in \($0)" } ?? ""
            equal(bg, "a \(expected.seconds)s \(expected.reason) gap\(named) is titled the same",
                  described.title, expected.title)
            equal(bg, "and explained the same",
                  described.detail, expected.detail)
        }

        // A week — the figures, the seven days, the rhythm grid, and the plain-language
        // read of its busiest cell.
        let wg = "week summary"
        let week = computeWeekSummary(
            events: fixture.week.events.map(event),
            dayStarts: fixture.week.dayStarts,
            now: fixture.week.now,
            calendar: calendar
        )
        let wex = fixture.week.expected
        equal(wg, "the week's active total", week.activeSeconds, wex.activeSeconds)
        equal(wg, "and how it reads", week.activeLabel, wex.activeLabel)
        equal(wg, "sessions across the week", week.sessionCount, wex.sessionCount)
        equal(wg, "distinct applications", week.appsUsed, wex.appsUsed)
        equal(wg, "seven days, oldest first", week.days.map(\.dayStart), wex.days.map(\.dayStart))
        equal(wg, "each named by its weekday", week.days.map(\.weekdayShort), wex.days.map(\.weekdayShort))
        equal(wg, "and its date", week.days.map(\.dayOfMonth), wex.days.map(\.dayOfMonth))
        equal(wg, "each day's active seconds",
              week.days.map(\.activeSeconds), wex.days.map { Int($0.activeSeconds) })
        equal(wg, "and its session count",
              week.days.map(\.sessionCount), wex.days.map(\.sessionCount))
        equal(wg, "a day with nothing recorded is rest, not a gap",
              week.days.map(\.isEmpty), wex.days.map(\.isEmpty))
        equal(wg, "today is marked", week.days.map(\.isToday), wex.days.map(\.isToday))
        equal(wg, "each day's hourly arc",
              week.days.map(\.arc), wex.days.map { $0.arc.map(Int.init) })
        equal(wg, "applications ordered by time, ties holding their first-seen order",
              week.apps.map(\.applicationName), wex.apps.map(\.applicationName))
        equal(wg, "with the same totals", week.apps.map(\.seconds), wex.apps.map(\.seconds))
        equal(wg, "and the same days-used counts",
              week.apps.map(\.daysUsed), wex.apps.map(\.daysUsed))
        check(wg, "and shares that match to four places",
              zip(week.apps, wex.apps).allSatisfy { abs($0.share - $1.share) < 0.0001 })
        equal(wg, "the rhythm grid, weekday by hour",
              week.rhythm, wex.rhythm.map { $0.map(Int.init) })
        equal(wg, "the busiest cell's weekday", week.peak?.weekday, wex.peak?.weekday)
        equal(wg, "and its hour", week.peak?.hour, wex.peak?.hour)
        equal(wg, "and how long was spent there",
              week.peak?.seconds, wex.peak.map { Int($0.seconds) })
        equal(wg, "read back in plain language",
              week.peak.map(describePeak), wex.peakLabel)
        for expected in fixture.week.peakCases {
            equal(wg, "hour \(expected.hour) on weekday \(expected.weekday) reads the same",
                  describePeak(WeekSummary.Peak(
                      weekday: expected.weekday, hour: expected.hour, seconds: expected.seconds
                  )),
                  expected.label)
        }

        // Recurring application combinations. A one-off pairing must not read as a habit,
        // and a single-app session is not a combination at all.
        let fg = "workflows"
        let workflowSessions = sessionsForWeek(
            fixture.workflows.events.map(event),
            now: fixture.workflows.now,
            calendar: calendar
        )
        equal(fg, "the fixture's sessions derive the same here",
              workflowSessions.count, fixture.workflows.sessionCount)
        let detected = detectWorkflows(workflowSessions)
        let wfx = fixture.workflows.expected
        equal(fg, "only recurring combinations, ordered by time with ties by first seen",
              detected.map(\.id), wfx.map(\.id))
        equal(fg, "each named for the category most of its sessions were",
              detected.map(\.title), wfx.map(\.title))
        equal(fg, "carrying that category", detected.map(\.category.rawValue), wfx.map(\.category))
        equal(fg, "the apps that define each, most-used first",
              detected.map { $0.apps.map(\.applicationName) },
              wfx.map { $0.apps.map(\.applicationName) })
        equal(fg, "identified the same way",
              detected.map { $0.apps.map { $0.bundleIdentifier ?? "" } },
              wfx.map { $0.apps.map { $0.bundleIdentifier ?? "" } })
        equal(fg, "with the same totals", detected.map(\.totalSeconds), wfx.map(\.totalSeconds))
        equal(fg, "across the same number of sessions",
              detected.map(\.sessionCount), wfx.map(\.sessionCount))

        // Chapters — eras, read from the headlines rather than the rows, which is why they
        // outlive a retention prune. Each rule has a case: a character change splits, a long
        // gap splits even when the character does not, and a day too quiet to anchor one is
        // dropped without breaking the run around it.
        let chg = "chapters"
        let chapters = detectChapters(
            fixture.chapters.summaries.map {
                DailySummary(
                    dayStart: $0.dayStart, activeSeconds: $0.activeSeconds,
                    topBundleID: $0.topBundleId, topAppName: $0.topAppName,
                    topSeconds: $0.topSeconds
                )
            },
            calendar: calendar
        )
        let cex = fixture.chapters.expected
        equal(chg, "the same eras, newest first", chapters.map(\.id), cex.map(\.id))
        equal(chg, "named descriptively until someone types a name",
              chapters.map { chapterDefaultName($0, calendar: calendar) }, cex.map(\.defaultName))
        equal(chg, "each with the character its days shared",
              chapters.map(\.category.rawValue), cex.map(\.category))
        equal(chg, "spanning the same days", chapters.map(\.dayCount), cex.map(\.dayCount))
        equal(chg, "between the same bounds",
              chapters.map { [$0.startDay, $0.endDay] }, cex.map { [$0.startDay, $0.endDay] })
        equal(chg, "holding the same active time",
              chapters.map(\.totalActiveSeconds), cex.map(\.totalActiveSeconds))
        equal(chg, "led by the same applications, most days first",
              chapters.map { $0.apps.map(\.applicationName) },
              cex.map { $0.apps.map(\.applicationName) })
        equal(chg, "each leading the same number of days",
              chapters.map { $0.apps.map(\.days) }, cex.map { $0.apps.map(\.days) })
        equal(chg, "represented by the same fullest day",
              chapters.map(\.representativeDay), cex.map(\.representativeDay))
        equal(chg, "and listing the same days, newest first",
              chapters.map(\.days), cex.map(\.days))

        // The autobiography. Prose is the whole feature, so the sentences are compared as
        // text: a paragraph that is *nearly* right is wrong, and only the words show it.
        let abg = "autobiography"
        let summaries = fixture.chapters.summaries.map {
            DailySummary(
                dayStart: $0.dayStart, activeSeconds: $0.activeSeconds,
                topBundleID: $0.topBundleId, topAppName: $0.topAppName,
                topSeconds: $0.topSeconds
            )
        }
        let reflectionCounts = ["m-2026-0": 3, "y-2026": 1]
        let periods = listPeriods(summaries, calendar: calendar, locale: environment.locale)
        let abx = fixture.autobiography.expected
        equal(abg, "the weeks, months and years the history touches, newest first",
              periods.map(\.key), abx.map(\.key))
        equal(abg, "each labelled the same", periods.map(\.label), abx.map(\.label))
        equal(abg, "and spanning the same days",
              periods.map { [$0.start, $0.end] }, abx.map { [$0.start, $0.end] })
        let told = periods.map { period in
            summarizePeriod(
                period, summaries: summaries,
                reflectionCount: reflectionCounts[period.key] ?? 0,
                calendar: calendar, locale: environment.locale
            )
        }
        equal(abg, "active days", told.map(\.activeDays), abx.map(\.activeDays))
        equal(abg, "total time", told.map(\.totalActiveSeconds), abx.map(\.totalActiveSeconds))
        equal(abg, "the kind of work that led",
              told.map { $0.dominantCategory?.rawValue }, abx.map(\.dominantCategory))
        equal(abg, "the tools reached for, most days first",
              told.map { $0.topApps.map(\.applicationName) },
              abx.map { $0.topApps.map(\.applicationName) })
        equal(abg, "the fullest day", told.map { $0.busiestDay?.day }, abx.map { $0.busiestDay?.day })
        equal(abg, "and every sentence, word for word",
              told.map(\.sentences), abx.map(\.sentences))

        // The archive. Its figures live inside a view upstream rather than in a module, so
        // the fixture re-declares them — the same compromise `sessionMatches` needed, and
        // the same reason: the alternative is nothing checking them at all.
        let lg = "the archive"
        if let lex = fixture.legacy.expected, let legacy = computeLegacy(summaries, calendar: calendar) {
            equal(lg, "when it begins", legacy.firstDay, lex.firstDay)
            equal(lg, "and where it has reached", legacy.lastDay, lex.lastDay)
            equal(lg, "active days", legacy.activeDays, lex.activeDays)
            equal(lg, "total time", legacy.totalSeconds, lex.totalSeconds)
            equal(lg, "the years it spans, newest first", legacy.years, lex.years)
            equal(lg, "the applications that ran through it",
                  legacy.favourites.map(\.applicationName), lex.favorites.map(\.name))
            equal(lg, "with the same time behind each",
                  legacy.favourites.map(\.seconds), lex.favorites.map(\.seconds))
            equal(lg, "across the same days",
                  legacy.favourites.map(\.days), lex.favorites.map(\.days))
        }
        check(lg, "no history is no archive, rather than an empty one",
              computeLegacy([], calendar: calendar) == nil)

        // Moments — prose again, so compared as text. Each kind has a threshold and the
        // fixture crosses every one it can, including a first-time-in app inside the seven
        // days that make it notable and one outside that must not appear.
        let mog = "moments"
        let seed = MomentSeed(
            firstEventAt: fixture.moments.seed.firstEventAt,
            appCount: fixture.moments.seed.appCount,
            appFirstSeen: fixture.moments.seed.appFirstSeen.map {
                MomentSeed.FirstSeen(
                    applicationName: $0.applicationName,
                    bundleIdentifier: $0.bundleIdentifier,
                    appPath: nil, firstAt: $0.firstAt
                )
            }
        )
        let moments = detectMoments(
            seed: seed, summaries: summaries,
            events: fixture.moments.events.map(event),
            now: fixture.moments.now,
            calendar: calendar, locale: environment.locale
        )
        let mex = fixture.moments.expected
        equal(mog, "the same moments, in the order they deserve attention",
              moments.map(\.kind.rawValue), mex.map(\.kind))
        equal(mog, "each keyed the same", moments.map(\.key), mex.map(\.key))
        equal(mog, "titled the same", moments.map(\.title), mex.map(\.title))
        equal(mog, "and told word for word", moments.map(\.detail), mex.map(\.detail))
        equal(mog, "each opening the right day", moments.map(\.dayStart), mex.map(\.dayStart))
        check(mog, "an application first seen more than a week ago is not news",
              !moments.contains { $0.key == "new-com.apple.Music" })
        equal(mog, "the day's featured moment is chosen from the day itself",
              pickDailyQuote(moments, now: fixture.moments.now, calendar: calendar)?.key,
              fixture.moments.quoteKey)

        // The canvas graph, and the constellation under it. Every node and every edge is
        // compared: an explorable landscape whose links are subtly wrong is worse than none.
        let cvg = "canvas"
        let stars = buildConstellation(workflowSessions, maxNodes: 16)
        let cvx = fixture.canvas
        equal(cvg, "the busiest applications, most time first",
              stars.nodes.map(\.key), cvx.constellation.nodes.map(\.key))
        equal(cvg, "each with the same time behind it",
              stars.nodes.map(\.totalSeconds), cvx.constellation.nodes.map(\.totalSeconds))
        equal(cvg, "across the same sessions",
              stars.nodes.map(\.sessionCount), cvx.constellation.nodes.map(\.sessionCount))
        equal(cvg, "tied by the same pairs, strongest first",
              stars.edges.map { [$0.a, $0.b] },
              cvx.constellation.edges.map { [$0.a, $0.b] })
        equal(cvg, "with the same weights",
              stars.edges.map(\.weight), cvx.constellation.edges.map(\.weight))
        equal(cvg, "and the same strongest tie", stars.maxWeight, cvx.constellation.maxWeight)

        let canvasProjects = detectProjects(workflowSessions).map {
            CanvasProject(
                id: $0.id, name: projectDefaultName($0), category: $0.category,
                apps: $0.apps, totalSeconds: $0.totalSeconds, sessionCount: $0.sessionCount
            )
        }
        let canvasChapters = detectChapters(summaries, calendar: calendar).map {
            CanvasChapter(
                id: $0.id, name: chapterDefaultName($0, calendar: calendar),
                category: $0.category, apps: $0.apps,
                totalActiveSeconds: $0.totalActiveSeconds, dayCount: $0.dayCount,
                startDay: $0.startDay, endDay: $0.endDay
            )
        }
        let graph = buildCanvas(
            sessions: workflowSessions, projects: canvasProjects,
            chapters: canvasChapters, moments: moments,
            calendar: calendar, locale: environment.locale
        )
        equal(cvg, "the same nodes, in the same order",
              graph.nodes.map(\.id), cvx.expected.nodes.map(\.id))
        equal(cvg, "of the same kinds",
              graph.nodes.map(\.type.rawValue), cvx.expected.nodes.map(\.type))
        equal(cvg, "labelled the same", graph.nodes.map(\.label), cvx.expected.nodes.map(\.label))
        equal(cvg, "with the same supporting line",
              graph.nodes.map(\.subtitle), cvx.expected.nodes.map(\.subtitle))
        equal(cvg, "weighted the same", graph.nodes.map(\.weight), cvx.expected.nodes.map(\.weight))
        equal(cvg, "and opening the same thing",
              graph.nodes.map(\.ref), cvx.expected.nodes.map(\.ref))
        equal(cvg, "the same edges, in the same order",
              graph.edges.map { [$0.a, $0.b] }, cvx.expected.edges.map { [$0.a, $0.b] })
        equal(cvg, "of the same kinds",
              graph.edges.map(\.kind.rawValue), cvx.expected.edges.map(\.kind))
        equal(cvg, "with the same weights",
              graph.edges.map(\.weight), cvx.expected.edges.map(\.weight))
        equal(cvg, "and the same strongest application tie",
              graph.maxAppWeight, cvx.expected.maxAppWeight)

        // Contextual memory. The scoring first: every producer scores in this vocabulary,
        // so if the arithmetic drifts, every memory in the app drifts with it.
        let mig = "memory scoring"
        let mc = fixture.memory
        func close(_ a: [Double], _ b: [Double]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 0.0001 }
        }
        check(mig, "clamped the same", close(mc.scoringCases.clamp.map(clamp01), mc.scoring.clamp))
        check(mig, "ramps, at both ends and between",
              close(mc.scoringCases.ramps.map { ramp($0[0], $0[1], $0[2]) }, mc.scoring.ramps))
        check(mig, "freshness decays the same",
              close(mc.scoringCases.freshness.map { freshness(ageDays: $0[0], halfLifeDays: $0[1]) },
                    mc.scoring.freshness))
        check(mig, "a blend averages only the signals actually present",
              close(mc.scoringCases.blends.map { parts in
                  blendConfidence(parts.map { (signal: $0.signal, weight: $0.weight) })
              }, mc.scoring.blends))
        check(mig, "days between", close(mc.scoringCases.days.map { daysBetween($0[0], $0[1]) },
                                          mc.scoring.days))
        check(mig, "what a session's own attributes argue",
              close(mc.scoringCases.sessions.map {
                  sessionMeaning(
                      activeSeconds: $0.activeSeconds,
                      bookmarked: $0.bookmarked ?? false, hasNote: $0.hasNote ?? false
                  )
              }, mc.scoring.sessions))
        check(mig, "and what a project's weight argues",
              close(mc.scoringCases.projects.map {
                  projectMeaning(totalSeconds: $0.totalSeconds, sessionCount: $0.sessionCount)
              }, mc.scoring.projects))
        equal(mig, "each threshold reads the same",
              mc.scoringCases.thresholds.map(confidenceThresholdLabel), mc.scoring.labels)

        // Selection, including the one that matters most: nothing clears the bar.
        let msg = "memory selection"
        for (input, expected) in zip(mc.selectionCases, mc.selection) {
            let candidates = input.candidates.map {
                MemoryCandidate(id: $0.id, kind: .echo, confidence: $0.confidence, headline: $0.id)
            }
            let options = MemorySelection(
                threshold: input.options.threshold,
                dismissed: Set(input.options.dismissed ?? []),
                archived: Set(input.options.archived ?? [])
            )
            equal(msg, "\(expected.name): the same candidates survive",
                  eligibleMemories(candidates, options).map(\.id), expected.eligible)
            equal(msg, "\(expected.name): and the same one is chosen",
                  selectLivingMemory(candidates, options)?.id, expected.chosen)
        }

        // The producers, each over a case built to make it speak.
        let mpg = "memory producers"
        let memoryProjects = mc.projects.map { fixture in
            MemoryProject(
                id: fixture.id, name: fixture.name,
                apps: fixture.apps.map {
                    Project.App(
                        applicationName: $0.applicationName,
                        bundleIdentifier: $0.bundleIdentifier,
                        appPath: nil, seconds: $0.seconds
                    )
                },
                totalSeconds: fixture.totalSeconds, sessionCount: fixture.sessionCount,
                firstSeen: fixture.firstSeen, lastActive: fixture.lastActive,
                sessionStarts: fixture.sessions.map(\.startedAt)
            )
        }
        func compare(_ what: String, _ got: MemoryCandidate?, _ want: GroupingAndExport.MemoryCase.Produced?) {
            equal(mpg, "\(what): the same id", got?.id, want?.id)
            equal(mpg, "\(what): the same kind", got?.kind.rawValue, want?.kind)
            equal(mpg, "\(what): told the same", got?.headline, want?.headline)
            equal(mpg, "\(what): and supported the same", got?.detail, want?.detail)
            check(mpg, "\(what): scored the same",
                  abs((got?.confidence ?? -1) - (want?.confidence ?? -1)) < 0.0001)
        }
        compare("a long gap since you last opened something",
                detectRightTime(
                    events: mc.rightTimeEvents.map(event), projects: memoryProjects,
                    now: mc.now, calendar: calendar
                ),
                mc.producers.rightTime)
        compare("a thread picked back up",
                detectThreadUpdate(
                    memoryProjects, now: mc.now, calendar: calendar, locale: environment.locale
                ),
                mc.producers.thread)
        compare("today echoing older work",
                detectEcho(
                    events: mc.echoEvents.map(event), projects: memoryProjects,
                    now: mc.now, calendar: calendar, locale: environment.locale
                ),
                mc.producers.echo)

        // Anniversaries and the forgotten, the last two producers of the cluster. An
        // anniversary only fires on an exact date, so the fixture's clock *is* one.
        let ang = "anniversaries and the forgotten"
        let anniversarySeed = MomentSeed(
            firstEventAt: mc.anniversarySeed.firstEventAt,
            appCount: mc.anniversarySeed.appCount,
            appFirstSeen: mc.anniversarySeed.appFirstSeen.map {
                MomentSeed.FirstSeen(
                    applicationName: $0.applicationName,
                    bundleIdentifier: $0.bundleIdentifier,
                    appPath: nil, firstAt: $0.firstAt
                )
            }
        )
        let memoryBookmarks = mc.bookmarks.map {
            SessionAnnotation(
                sessionStart: $0.sessionStart, note: $0.note,
                bookmarked: $0.bookmarked, tags: [], updatedAt: $0.updatedAt
            )
        }
        let memoryReflections = mc.reflections.map {
            DatedText(dayStart: $0.dayStart, text: $0.text)
        }
        let anniversaries = detectAnniversaries(
            seed: anniversarySeed, projects: memoryProjects,
            bookmarks: memoryBookmarks, reflections: memoryReflections,
            now: mc.anniversaryNow, calendar: calendar
        )
        equal(ang, "the same anniversaries fall today",
              anniversaries.map(\.id), mc.anniversaries.map(\.id))
        equal(ang, "each said the same way",
              anniversaries.map(\.headline), mc.anniversaries.map(\.headline))
        check(ang, "and scored the same",
              zip(anniversaries, mc.anniversaries)
                  .allSatisfy { abs($0.confidence - $1.confidence) < 0.0001 })

        let forgotten = detectForgotten(
            projects: memoryProjects, bookmarks: memoryBookmarks,
            reflections: memoryReflections, now: mc.now, calendar: calendar
        )
        equal(ang, "the same things have been let lie, most confident first",
              forgotten.map(\.id), mc.forgotten.map(\.id))
        equal(ang, "each said the same way",
              forgotten.map(\.headline), mc.forgotten.map(\.headline))
        equal(ang, "with the same excerpt where there is one",
              forgotten.map { $0.detail ?? "" }, mc.forgotten.map { $0.detail ?? "" })
        check(ang, "and scored the same",
              zip(forgotten, mc.forgotten)
                  .allSatisfy { abs($0.confidence - $1.confidence) < 0.0001 })
        check(ang, "everything forgotten can be archived as well as dismissed",
              forgotten.allSatisfy(\.archivable))

        // The Timeline's filter buckets. Fewer than the session categories on purpose, and
        // the two that fall through to Other are the ones worth pinning.
        let fcg = "filter categories"
        equal(fcg, "the same buckets, in the same order",
              FilterCategory.allCases.map(\.rawValue), fixture.filters.categories)
        for mapped in fixture.filters.mapped {
            guard let category = SessionCategory(rawValue: mapped.category) else {
                check(fcg, "the port knows the category '\(mapped.category)'", false)
                continue
            }
            let session = ActivitySession(
                title: "", category: category, startedAt: 0, endedAt: 0,
                spanSeconds: 0, activeSeconds: 0, apps: [], events: [], switches: 0
            )
            equal(fcg, "a \(mapped.category) session filters as \(mapped.bucket)",
                  sessionFilterCategory(session).rawValue, mapped.bucket)
        }

        // The pool a surprise is drawn from. The order matters as much as the membership:
        // it is what makes a seeded pick land on the same day twice.
        equal(mog, "the days worth arriving on, in the same order",
              surprisePool(
                  moments: moments, summaries: summaries,
                  bookmarkStarts: mc.bookmarks.map(\.sessionStart),
                  now: fixture.moments.now, calendar: calendar
              ),
              mc.surprise)
        check(mog, "and today is never one of them",
              !surprisePool(
                  moments: moments, summaries: summaries,
                  bookmarkStarts: mc.bookmarks.map(\.sessionStart),
                  now: fixture.moments.now, calendar: calendar
              ).contains(startOfLocalDay(fixture.moments.now, calendar: calendar)))

        // The morning briefing, including the cases where it says nothing: after noon, and
        // when yesterday holds nothing to reflect on.
        let mbg = "morning briefing"
        let briefingSummaries = fixture.briefings.summaries.map {
            DailySummary(
                dayStart: $0.dayStart, activeSeconds: $0.activeSeconds,
                topBundleID: $0.topBundleId, topAppName: $0.topAppName,
                topSeconds: $0.topSeconds
            )
        }
        for (input, expected) in zip(fixture.briefings.cases, fixture.briefings.expected) {
            let built = buildMorningBriefing(
                now: input.now,
                yesterdayEvents: input.yesterdayEvents.map(event),
                summaries: briefingSummaries,
                projects: memoryProjects,
                monthAgo: input.monthAgo.map { ($0.dayStart, $0.topApp) },
                bookmarkStarts: input.bookmarkStarts ?? [],
                calendar: calendar
            )
            guard let want = expected.result else {
                check(mbg, "\(expected.name): nothing is said", built == nil)
                continue
            }
            guard let built else {
                check(mbg, "\(expected.name): a briefing is assembled", false)
                continue
            }
            equal(mbg, "\(expected.name): for the right day", built.dayStart, want.dayStart)
            equal(mbg, "\(expected.name): yesterday's active time",
                  built.yesterdayActiveSeconds, want.yesterdayActiveSeconds)
            equal(mbg, "\(expected.name): and what led it",
                  built.yesterdayTopApp, want.yesterdayTopApp)
            equal(mbg, "\(expected.name): the longest stretch in it",
                  built.longestFocusSeconds, want.longestFocusSeconds)
            equal(mbg, "\(expected.name): the thread worth continuing",
                  built.continuedProject?.id, want.continuedProject?.id)
            equal(mbg, "\(expected.name): and the oldest bookmark still waiting",
                  built.pendingBookmark, want.pendingBookmark)
        }

        // Rituals — the quiet patterns in a run of days. A part of the day only counts once
        // the same app has led it more than once, which is the guard against a single
        // sitting reading as a habit.
        let rtg = "rituals"
        let ritualEvents = fixture.rituals.events.map(event)
        let rituals = detectRituals(
            sessions: sessionsForWeek(ritualEvents, now: fixture.rituals.now, calendar: calendar),
            events: ritualEvents,
            calendar: calendar
        )
        let rex = fixture.rituals.expected
        equal(rtg, "the parts of the day that have settled into one, in day order",
              rituals.slots.map(\.part), rex.slots.map(\.part))
        equal(rtg, "each led by the same application",
              rituals.slots.map(\.app.applicationName), rex.slots.map(\.applicationName))
        equal(rtg, "on the same number of distinct days",
              rituals.slots.map(\.app.days), rex.slots.map(\.days))
        equal(rtg, "the application a day most often begins with",
              rituals.firstApp?.applicationName, rex.firstApp?.applicationName)
        equal(rtg, "and how many days it began",
              rituals.firstApp?.days, rex.firstApp?.days)
        check(rtg, "a part led on a single day is not a ritual",
              !rituals.slots.contains { $0.part == "Afternoon" })

        // Per-application totals. Idle stretches are excluded first, as at every call site
        // upstream: "how long in this app" means time at the keyboard, not a Mac left open
        // with the app in front.
        let apg = "application totals"
        let stats = computeAppStats(
            excludeIdleStretches(fixture.appStats.events.map(event), now: fixture.appStats.now),
            now: fixture.appStats.now
        )
        let asx = fixture.appStats.expected
        equal(apg, "most-used first, ties holding their first-seen order",
              stats.map(\.applicationName), asx.map(\.applicationName))
        equal(apg, "with the same totals", stats.map(\.totalSeconds), asx.map(\.totalSeconds))
        equal(apg, "counting how many times each came to the front",
              stats.map(\.sessionCount), asx.map(\.sessionCount))
        equal(apg, "and when each was last used",
              stats.map(\.lastUsedAt), asx.map(\.lastUsedAt))
        equal(apg, "an app with no bundle identifier is counted under its name",
              stats.map { $0.bundleIdentifier ?? "" }, asx.map { $0.bundleIdentifier ?? "" })
        check(apg, "a stretch too long to be use is not counted as use",
              !stats.contains { $0.applicationName == "Preview" })
        check(apg, "and a row still open is measured against now",
              stats.contains { $0.applicationName == "Mail" && $0.totalSeconds == 300 })

        // Resume — which session to offer, and how the moment reads. The point of the
        // feature is that the session you are *in* is not the one to offer, so the checks
        // turn on where `now` sits relative to the last row's end.
        let rsg = "resume"
        for (input, expected) in zip(fixture.resume.cases, fixture.resume.expected) {
            let target = findResumeTarget(
                buildTimeline(input.events.map(event), now: input.now, calendar: calendar),
                now: input.now,
                calendar: calendar
            )
            guard let wanted = expected.target else {
                check(rsg, "\(expected.name): nothing to offer", target == nil)
                continue
            }
            guard let target else {
                check(rsg, "\(expected.name): a session is offered", false)
                continue
            }
            equal(rsg, "\(expected.name): the right session",
                  target.session.startedAt, wanted.sessionStart)
            equal(rsg, "\(expected.name): named the same",
                  target.session.title, wanted.sessionTitle)
            equal(rsg, "\(expected.name): resuming the right application",
                  target.app.applicationName, wanted.applicationName)
            equal(rsg, "\(expected.name): and knowing whether it was another day",
                  target.isEarlierDay, wanted.isEarlierDay)
            equal(rsg, "\(expected.name): read back in words",
                  formatWhen(target.session.endedAt, now: input.now,
                             calendar: calendar, locale: environment.locale),
                  wanted.when)
        }
        for expected in fixture.resume.whenCases {
            equal(rsg, "a moment \(expected.now - expected.at)ms ago reads the same",
                  formatWhen(expected.at, now: expected.now,
                             calendar: calendar, locale: environment.locale),
                  expected.label)
        }

        // How two applications are used together. A pair must have been switched between
        // at least twice to count, so a single incidental hop never reads as a bond.
        let rlg = "relationships"
        let rlx = fixture.relationships
        let partners = computeWorkflowPartners(workflowSessions, anchorKey: rlx.anchorKey)
        equal(rlg, "the applications most entwined with the anchor, strongest first",
              partners.map(\.identity.applicationName), rlx.partners.map(\.applicationName))
        equal(rlg, "switched between the same number of times",
              partners.map(\.switches), rlx.partners.map(\.switches))
        equal(rlg, "across the same shared sessions",
              partners.map(\.sharedSessions), rlx.partners.map(\.sharedSessions))
        equal(rlg, "leaning the same way",
              partners.map { [$0.forward, $0.backward] },
              rlx.partners.map { [$0.forward, $0.backward] })
        equal(rlg, "for the same average length",
              partners.map(\.averageTogetherSeconds), rlx.partners.map(\.avgTogetherSeconds))

        let pair = computeRelationship(
            workflowSessions, keyA: rlx.anchorKey, keyB: rlx.partnerKey
        )
        equal(rlg, "a pair's switches", pair?.switches, rlx.relationship?.switches)
        equal(rlg, "which way they go",
              pair.map { [$0.aToB, $0.bToA] }, rlx.relationship.map { [$0.aToB, $0.bToA] })
        equal(rlg, "how many sessions they shared",
              pair?.sharedSessions, rlx.relationship?.sharedSessions)
        equal(rlg, "and how long those ran",
              pair?.averageTogetherSeconds, rlx.relationship?.avgTogetherSeconds)
        equal(rlg, "the shared sessions, newest first",
              pair?.sessions.map(\.startedAt), rlx.relationship?.sessionStarts)
        check(rlg, "two applications that never met have no relationship, rather than an empty one",
              (computeRelationship(
                  workflowSessions, keyA: rlx.anchorKey, keyB: "com.example.never"
              ) == nil) == rlx.hasNoRelationship)

        // Projects — the same grouping, keeping the whole span. Apps are aggregated across
        // every session here rather than taken from the first, which is the difference from
        // a workflow and the thing most likely to be got wrong.
        let pg = "projects"
        let projects = detectProjects(workflowSessions)
        let pex = fixture.workflows.projects
        equal(pg, "most recently active first", projects.map(\.id), pex.map(\.id))
        equal(pg, "named descriptively until someone types a name",
              projects.map(projectDefaultName), pex.map(\.defaultName))
        equal(pg, "carrying the category most of their sessions were",
              projects.map(\.category.rawValue), pex.map(\.category))
        equal(pg, "with time aggregated across every session",
              projects.map { $0.apps.map(\.seconds) }, pex.map { $0.apps.map(\.seconds) })
        equal(pg, "and the apps ordered by it",
              projects.map { $0.apps.map(\.applicationName) },
              pex.map { $0.apps.map(\.applicationName) })
        equal(pg, "totals", projects.map(\.totalSeconds), pex.map(\.totalSeconds))
        equal(pg, "session counts", projects.map(\.sessionCount), pex.map(\.sessionCount))
        equal(pg, "when each was first seen", projects.map(\.firstSeen), pex.map(\.firstSeen))
        equal(pg, "and last active", projects.map(\.lastActive), pex.map(\.lastActive))
        equal(pg, "every session under each, newest first",
              projects.map { $0.sessions.map(\.startedAt) }, pex.map(\.sessionStarts))

        for expected in fixture.resume.dayLabels {
            equal(rsg, "how long ago \(expected.at) reads",
                  relativeDayLabel(expected.at, now: expected.now,
                                   calendar: calendar, locale: environment.locale),
                  expected.relative)
            equal(rsg, "and its short date",
                  shortDateLabel(expected.at, calendar: calendar, locale: environment.locale),
                  expected.short)
        }

        let rg2 = "report text"
        let reportSessions = buildTimeline(
            fixture.report.events.map(event), now: fixture.report.now, calendar: calendar
        )
            .compactMap { if case .session(let s) = $0 { return s } else { return nil } }
        equal(rg2, "the fixture's sessions derive the same here",
              reportSessions.count, fixture.report.annotations.isEmpty ? 0 : 2)
        let reportEntries = reportSessions.enumerated().map { index, session in
            ReplayCore.Report.Entry(
                session: session,
                annotation: index < fixture.report.annotations.count
                    ? SessionAnnotation(
                        sessionStart: fixture.report.annotations[index].sessionStart,
                        note: fixture.report.annotations[index].note,
                        bookmarked: fixture.report.annotations[index].bookmarked,
                        tags: fixture.report.annotations[index].tags
                    )
                    : nil
            )
        }
        let exportedAt = Date(timeIntervalSince1970: Double(fixture.exportedAtMillis) / 1000)

        // Markdown and CSV are compared as text, because the text *is* the artefact: a
        // report is a file someone keeps, and a stray meridiem or a missing quote is a
        // difference they would see.
        equalText(rg2, "markdown matches the reference, character for character",
              withPlainSpaces(ReplayCore.Report.build(
                  .markdown, label: fixture.report.label, entries: reportEntries,
                  now: exportedAt, environment: environment
              )),
              withPlainSpaces(fixture.report.expected.markdown))
        equalText(rg2, "csv matches the reference, character for character",
              withPlainSpaces(ReplayCore.Report.build(
                  .csv, label: fixture.report.label, entries: reportEntries,
                  now: exportedAt, environment: environment
              )),
              withPlainSpaces(fixture.report.expected.csv))

        // JSON is compared as structure: both sides pretty-print, but key order is not part
        // of the format and pinning it would fail for a reason no consumer would care about.
        let ours = try? JSONSerialization.jsonObject(
            with: Data(ReplayCore.Report.build(
                .json, label: fixture.report.label, entries: reportEntries,
                now: exportedAt, environment: environment
            ).utf8)
        ) as? [String: Any]
        let theirs = try? JSONSerialization.jsonObject(
            with: Data(fixture.report.expected.json.utf8)
        ) as? [String: Any]
        check(rg2, "json parses on both sides", ours != nil && theirs != nil)
        if let ours, let theirs {
            equal(rg2, "the same keys", ours.keys.sorted(), theirs.keys.sorted())
            equal(rg2, "the same exported-at, milliseconds included",
                  ours["exportedAt"] as? String, theirs["exportedAt"] as? String)
            equal(rg2, "the same scope", ours["scope"] as? String, theirs["scope"] as? String)
            equal(rg2, "the same session count",
                  ours["sessionCount"] as? Int, theirs["sessionCount"] as? Int)
            let oursSessions = (ours["sessions"] as? [[String: Any]]) ?? []
            let theirsSessions = (theirs["sessions"] as? [[String: Any]]) ?? []
            equal(rg2, "the same number of sessions serialised",
                  oursSessions.count, theirsSessions.count)
            for (index, theirSession) in theirsSessions.enumerated() {
                guard index < oursSessions.count else { break }
                let ourSession = oursSessions[index]
                equal(rg2, "session \(index) keys",
                      ourSession.keys.sorted(), theirSession.keys.sorted())
                for key in ["title", "startedAt", "endedAt", "category", "note"] {
                    equal(rg2, "session \(index) \(key)",
                          ourSession[key] as? String, theirSession[key] as? String)
                }
                equal(rg2, "session \(index) activeSeconds",
                      ourSession["activeSeconds"] as? Int, theirSession["activeSeconds"] as? Int)
                equal(rg2, "session \(index) bookmarked",
                      ourSession["bookmarked"] as? Bool, theirSession["bookmarked"] as? Bool)
                equal(rg2, "session \(index) tags",
                      ourSession["tags"] as? [String], theirSession["tags"] as? [String])
            }
        }

        // Export scopes — which sessions a report covers.
        let sg = "export scopes"
        equal(sg, "the port offers every scope the reference does",
              ReplayCore.Report.Scope.allCases.map(\.rawValue).sorted(),
              fixture.scopes.offered.sorted())

        let scopeSessions = ReplayCore.Report.sessions(
            in: fixture.scopes.events.map(event), now: fixture.scopes.now, calendar: calendar
        )
        equal(sg, "the same sessions derive from a month of events",
              scopeSessions.map(\.startedAt), fixture.scopes.allSessionStarts)

        var scopeAnnotations: [Int64: SessionAnnotation] = [:]
        for annotation in fixture.scopes.annotations {
            scopeAnnotations[annotation.sessionStart] = SessionAnnotation(
                sessionStart: annotation.sessionStart,
                note: annotation.note,
                bookmarked: annotation.bookmarked,
                tags: annotation.tags
            )
        }

        for scope in ReplayCore.Report.Scope.allCases {
            guard let expected = fixture.scopes.expected[scope.rawValue] else {
                check(sg, "\(scope.rawValue) is covered by the fixture", false, "no expectation recorded")
                continue
            }
            let selected = ReplayCore.Report.select(
                scope,
                sessions: scopeSessions,
                annotations: scopeAnnotations,
                todayStart: fixture.scopes.todayStart
            )
            equal(sg, "\(scope.rawValue) selects the same sessions",
                  selected.map(\.session.startedAt), expected)
        }
        // Stated separately because it is the rule most easily lost: a note of only
        // whitespace is not a note, and must not put a session in that scope.
        check(sg, "a whitespace-only note does not count as a note",
              (fixture.scopes.expected["notes"] ?? []).count
                  < fixture.scopes.annotations.filter { !$0.note.isEmpty }.count)

        // Search — the predicates that decide whether a session is findable.
        let hg = "search"
        for query in fixture.search.queries {
            guard let expected = fixture.search.expected[query] else {
                check(hg, "\(query) is covered by the fixture", false, "no expectation recorded")
                continue
            }
            equal(hg, "\"\(query)\" matches the same sessions",
                  scopeSessions.filter {
                      ReplayCore.Search.matches(
                          session: $0, annotation: scopeAnnotations[$0.startedAt], query: query
                      )
                  }.map(\.startedAt),
                  expected.matches)
            equal(hg, "\"\(query)\" finds the same sessions by application",
                  scopeSessions.filter {
                      ReplayCore.Search.usesApp(session: $0, applicationName: query)
                  }.map(\.startedAt),
                  expected.usesApp)
        }
        // Stated on its own because it is the distinction most easily collapsed: the
        // application predicate is exact, so a lowercase name finds nothing while the
        // exact one finds everything. Substring discovery is a different function.
        check(hg, "the application predicate is exact, not a substring",
              (fixture.search.expected["safari"]?.usesApp ?? []).isEmpty
                  && !(fixture.search.expected["Safari"]?.usesApp ?? []).isEmpty)
        equal(hg, "substring discovery is what finds an app by a lowercase name",
              ReplayCore.Search.apps(matching: "safari", in: scopeSessions).map(\.applicationName),
              ["Safari"])

        // Story Mode — a day told back in sentences.
        //
        // Compared as text, because the text *is* the feature: every clause is a claim
        // about the day, and a wrong word is a wrong claim. The cases are chosen so each
        // rule fires or is suppressed, including a day whose two longest stretches tie —
        // the reference keeps the first, Swift's `max(by:)` would keep the last and
        // narrate a different application.
        let stg = "story mode"
        for (index, storyCase) in fixture.stories.cases.enumerated() {
            guard index < fixture.stories.expected.count else { break }
            let expected = fixture.stories.expected[index]
            let sessions = buildTimeline(
                storyCase.events.map(event), now: storyCase.now, calendar: calendar
            ).compactMap { if case .session(let s) = $0 { return s } else { return nil } }
            equal(stg, "\(storyCase.name): the same sessions derive",
                  sessions.count, expected.sessionCount)
            equal(stg, "\(storyCase.name): the same story",
                  DayStory.build(sessions, calendar: calendar), expected.sentences)
        }
        check(stg, "a day with nothing on it gets no story",
              DayStory.build([], calendar: calendar).isEmpty)

        // Collections — sessions gathered by the kind of work they were.
        //
        // Both orderings are tie-broken explicitly here, and the fixture is built so both
        // ties actually occur: two categories on equal totals, and two apps on equal time
        // inside one. JavaScript's sort is stable and falls back on insertion order without
        // saying so; Swift's is not, so an untie-broken port would reorder between launches
        // and pass a fixture that happened not to tie.
        let cg = "collections"
        equal(cg, "the same categories are collectable, in the same order",
              Collections.categories.map(\.category.rawValue),
              fixture.collections.definitions.map(\.category))
        equal(cg, "and carry the same labels — Admin is shown as Utilities",
              Collections.categories.map(\.label),
              fixture.collections.definitions.map(\.label))

        let collectionSessions = buildTimeline(
            fixture.collections.events.map(event),
            now: fixture.collections.now,
            calendar: calendar
        ).compactMap { if case .session(let s) = $0 { return s } else { return nil } }
        equal(cg, "the fixture's sessions derive the same here",
              collectionSessions.count, fixture.collections.sessionCount)

        let computed = Collections.compute(collectionSessions)
        equal(cg, "the same collections, fullest first",
              computed.map(\.category.rawValue), fixture.collections.expected.map(\.category))
        equal(cg, "with the same totals",
              computed.map(\.totalSeconds), fixture.collections.expected.map(\.totalSeconds))
        equal(cg, "and the same session counts",
              computed.map(\.sessionCount), fixture.collections.expected.map(\.sessionCount))
        for (index, expected) in fixture.collections.expected.enumerated() {
            guard index < computed.count else { break }
            equal(cg, "\(expected.category): the same apps, most time first",
                  computed[index].apps.map(\.applicationName),
                  expected.apps.map(\.applicationName))
            equal(cg, "\(expected.category): with the same times",
                  computed[index].apps.map(\.seconds), expected.apps.map(\.seconds))
        }
        check(cg, "a session the category table could not name is not collected",
              !computed.contains { $0.category == .other })
        check(cg, "an app list is capped",
              computed.allSatisfy { $0.apps.count <= Collections.appLimit })

        // Memories — which calendar day each offset lands on.
        //
        // The month-end cases are the point. JavaScript's Date normalises an overflowing
        // day (31 March minus a month is 3 March); Swift's `date(byAdding:)` clamps it to
        // 28 February. A memory labelled "one month ago" has to mean the same day in both
        // apps, so this pins the arithmetic rather than trusting either default.
        let memg = "memories"
        let historySummaries = fixture.history.summaries.map {
            DailySummary(
                dayStart: $0.dayStart, activeSeconds: $0.activeSeconds, topAppName: $0.topAppName
            )
        }
        for historyCase in fixture.history.cases {
            let when = ISO8601DateFormatter().string(from:
                Date(timeIntervalSince1970: Double(historyCase.now) / 1000)).prefix(10)
            equal(memg, "\(when): the offsets land on the same days",
                  Memories.targets(now: historyCase.now, calendar: calendar).map(\.dayStart),
                  historyCase.targets.map(\.dayStart))
            equal(memg, "\(when): and are labelled the same",
                  Memories.targets(now: historyCase.now, calendar: calendar).map(\.label),
                  historyCase.targets.map(\.label))
            equal(memg, "\(when): the same offsets have something to show",
                  Memories.find(
                      in: historySummaries, now: historyCase.now, calendar: calendar
                  ).map(\.range.key),
                  historyCase.found.map(\.key))
        }
        check(memg, "a day with a headline of zero is not a memory",
              Memories.find(
                  in: [DailySummary(dayStart: startOfLocalDay(t0, calendar: calendar) - dayMillis,
                                    activeSeconds: 0)],
                  now: t0, calendar: calendar
              ).isEmpty)

        // focus goals — the app's one evaluative surface, so its rules are checked rather
        // than trusted. The streak rule is the subtle one: an unfinished today must not
        // break a run, or every streak reads as broken every morning.
        let gg = "focus goal"
        equal(gg, "a goal under an hour reads as minutes", Goals.format(45), "45m")
        equal(gg, "a round hour reads in words", Goals.format(60), "1 hour")
        equal(gg, "more than one hour pluralises", Goals.format(120), "2 hours")
        equal(gg, "a mixed goal keeps both parts", Goals.format(330), "5h 30m")
        check(gg, "a preset is not custom", !Goals.isCustom(240))
        check(gg, "an off-grid target is", Goals.isCustom(45))

        let halfway = Goals.progress(activeSeconds: 1800, goalMinutes: 60)
        equal(gg, "progress is a fraction of the goal", halfway.fraction, 0.5)
        equal(gg, "and reports what is left", halfway.remainingSeconds, 1800)
        check(gg, "an unmet goal is not met", !halfway.met)
        let overshot = Goals.progress(activeSeconds: 7200, goalMinutes: 60)
        equal(gg, "overshooting clamps the ring rather than exceeding it", overshot.fraction, 1)
        equal(gg, "and leaves nothing to go", overshot.remainingSeconds, 0)
        check(gg, "a met goal is met", overshot.met)

        let yesterday = startOfLocalDay(t0) - dayMillis
        let dayBefore = yesterday - dayMillis
        let history = [
            DailySummary(dayStart: yesterday, activeSeconds: 7200, topBundleID: nil,
                         topAppName: nil, topSeconds: 0),
            DailySummary(dayStart: dayBefore, activeSeconds: 7200, topBundleID: nil,
                         topAppName: nil, topSeconds: 0),
        ]
        equal(gg, "an unfinished today keeps the run that ended yesterday",
              Goals.streak(summaries: history, todayStart: startOfLocalDay(t0),
                           todayActiveSeconds: 60, goalMinutes: 60), 2)
        equal(gg, "and today joins the run once it is met",
              Goals.streak(summaries: history, todayStart: startOfLocalDay(t0),
                           todayActiveSeconds: 7200, goalMinutes: 60), 3)
        equal(gg, "a missed day ends the run",
              Goals.streak(summaries: [history[0]], todayStart: startOfLocalDay(t0),
                           todayActiveSeconds: 60, goalMinutes: 60), 1)
        equal(gg, "no goal is no streak",
              Goals.streak(summaries: history, todayStart: startOfLocalDay(t0),
                           todayActiveSeconds: 7200, goalMinutes: 0), 0)

        // reports — what an export writes. Serialising is the whole feature, so the shapes
        // are checked rather than just the call not throwing.
        let xg = "report export"
        // Derived rather than hand-built, so what is serialised is what the app would
        // actually show — the same `buildTimeline` every surface reads.
        let reportEvents = [
            ActivityEvent(
                id: 1, type: .activated, applicationName: "Code",
                bundleIdentifier: "com.microsoft.VSCode", appPath: nil,
                startedAt: t0, endedAt: t0 + 600_000, duration: 600
            ),
            ActivityEvent(
                id: 2, type: .activated, applicationName: "Safari",
                bundleIdentifier: "com.apple.Safari", appPath: nil,
                startedAt: t0 + 600_000, endedAt: t0 + 900_000, duration: 300
            ),
        ]
        guard case .session(let reportSession)? = buildTimeline(reportEvents, now: t0 + 900_000).first
        else {
            check(xg, "a sample session could be derived", false, "buildTimeline produced no session")
            return Report(
                glazeVersion: constants.glazeVersion, glazeCommit: constants.glazeCommit,
                specRoot: root.path, checks: checks, fixtureResults: fixtureResults
            )
        }
        let sample = ReplayCore.Report.Entry(
            session: reportSession,
            annotation: SessionAnnotation(
                sessionStart: t0, note: "shipped it", bookmarked: true, tags: ["deep work"],
                updatedAt: t0
            )
        )

        let markdown = ReplayCore.Report.build(.markdown, label: "Today", entries: [sample])
        check(xg, "markdown leads with the scope it covers", markdown.hasPrefix("# Replay — Today"))
        check(xg, "a bookmarked session is starred", markdown.contains("\(reportSession.title) ⭐"))
        check(xg, "the note is quoted", markdown.contains("> shipped it"))
        check(xg, "tags carry their hash", markdown.contains("Tags: #deep work"))
        check(xg, "an empty export says so rather than being blank",
              ReplayCore.Report.build(.markdown, label: "Today", entries: []).contains("Nothing to export"))

        let csvText = ReplayCore.Report.build(.csv, label: "Today", entries: [sample])
        equal(xg, "csv has a header and a row per session", csvText.split(separator: "\n").count, 2)
        check(xg, "csv marks a bookmark", csvText.contains(",yes,"))
        equal(xg, "a cell with a comma is quoted", ReplayCore.Report.csvCell("a, b"), "\"a, b\"")
        equal(xg, "a quote inside a cell is doubled", ReplayCore.Report.csvCell("say \"hi\""), "\"say \"\"hi\"\"\"")
        equal(xg, "a plain cell is left alone", ReplayCore.Report.csvCell("plain"), "plain")

        let jsonText = ReplayCore.Report.build(.json, label: "Today", entries: [sample])
        let parsedReport = try? JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any]
        equal(xg, "json reports how many sessions it holds",
              (parsedReport?["sessionCount"] as? Int), 1)
        check(xg, "json carries the annotation",
              ((parsedReport?["sessions"] as? [[String: Any]])?.first?["note"] as? String) == "shipped it")

        // A backup round-trips through its own reader — the check that matters, because a
        // backup nobody can restore is not a backup.
        let backupRows = try store.rowsForBackup()
        let encoded = Backup.encode(rows: backupRows, appVersion: "test")
        let reread = try Backup.read(encoded)
        equal(xg, "a written backup reads back with every row", reread.rows.count, backupRows.count)
        equal(xg, "and its rows survive intact", reread.rows, backupRows)
        equal(xg, "the count it declares matches what it holds",
              reread.declaredCount, backupRows.count)

        // Clearing history means what it says: no rows, and no headline left behind.
        try store.upsertSummary(dayStart: startOfLocalDay(t0), now: t0)
        _ = try store.setBookmarked(sessionStart: t0, bookmarked: true, now: t0)
        _ = try store.clearAllHistory()
        equal(mg, "clearing history removes every row", try store.countRows(), 0)
        equal(mg, "and every headline",
              try store.dailySummaries(from: 0, to: t0 + dayMillis).count, 0)
        equal(mg, "and every annotation", try store.annotations(from: 0, to: t0 + dayMillis).count, 0)

        store.close()
        try? FileManager.default.removeItem(at: tmp)

        // backup format — the migration path off the Glaze app, so a mismatch here means
        // a user's exported history cannot be read.
        let g4 = "backup"
        equal(g4, "format string", Backup.format, constants.backup.format)
        equal(g4, "format version", Backup.version, constants.backup.version)
        equal(g4, "accepted row types",
              Backup.acceptedTypes.map(\.rawValue).sorted(),
              constants.backup.acceptedEventTypes.sorted())
        check(g4, "accepts idle rows — dropping them relabels away time as not-recorded",
              Backup.acceptedTypes.contains(.idle))

        // A backup written in the documented shape, read back, and imported twice: the
        // second import must be a no-op, which is what makes the operation safe to repeat.
        let backupURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-parity-backup-\(UUID().uuidString).json")
        let t1 = Int64(1_770_000_000_000)
        let backupJSON = """
            {
              "format": "\(Backup.format)",
              "version": \(Backup.version),
              "exportedAt": "2026-07-26T12:00:00.000Z",
              "appVersion": "\(constants.glazeVersion)",
              "eventCount": 4,
              "events": [
                {"type":"activated","application_name":"Code","bundle_identifier":"com.microsoft.VSCode",
                 "started_at":\(t1),"ended_at":\(t1 + 600_000),"duration":600,"metadata":null},
                {"type":"idle","application_name":"Away","bundle_identifier":null,
                 "started_at":\(t1 + 600_000),"ended_at":\(t1 + 1_200_000),"duration":600,"metadata":null},
                {"type":"activated","application_name":"Safari","bundle_identifier":"com.apple.Safari",
                 "started_at":\(t1 + 1_200_000),"ended_at":\(t1 + 1_500_000),"duration":300,"metadata":null},
                {"type":"nonsense","application_name":"","started_at":"not a number"}
              ]
            }
            """
        try backupJSON.write(to: backupURL, atomically: true, encoding: .utf8)

        let restoreDB = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-parity-restore-\(UUID().uuidString).db")
        let restoreStore = ActivityStore(path: restoreDB.path)
        try restoreStore.open()

        let parsed = try Backup.read(contentsOf: backupURL)
        equal(g4, "reads the valid rows", parsed.rows.count, 3)
        equal(g4, "drops the malformed row", parsed.skipped, 1)
        check(g4, "keeps the away row", parsed.rows.contains { $0.type == .idle })

        let first = try restoreStore.importBackup(from: backupURL, now: t1 + 2_000_000)
        equal(g4, "first import restores every valid row", first.imported, 3)
        equal(g4, "and stores them", try restoreStore.countRows(), 3)
        let second = try restoreStore.importBackup(from: backupURL, now: t1 + 2_000_000)
        equal(g4, "importing the same file again imports nothing", second.imported, 0)
        equal(g4, "skipping them instead", second.skipped, 3)
        equal(g4, "so the row count is unchanged", try restoreStore.countRows(), 3)

        do {
            _ = try Backup.read(Data(#"{"format":"something.else","events":[]}"#.utf8))
            check(g4, "a foreign format is refused", false, "it was accepted")
        } catch {
            check(g4, "a foreign format is refused", true)
        }

        restoreStore.close()
        try? FileManager.default.removeItem(at: restoreDB)
        try? FileManager.default.removeItem(at: backupURL)

        return Report(
            glazeVersion: constants.glazeVersion,
            glazeCommit: constants.glazeCommit,
            specRoot: root.path,
            checks: checks,
            fixtureResults: fixtureResults
        )
    }
}
