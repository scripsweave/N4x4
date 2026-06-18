// N4x4Complication.swift
// watchOS Widget Extension — a Watch-face complication that quick-launches the
// N4x4 Watch app. Target membership: the N4x4Complication Widget Extension
// target ONLY (not the N4x4Watch app target).

import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct N4x4ComplicationEntry: TimelineEntry {
    let date: Date
}

// MARK: - Provider

struct N4x4ComplicationProvider: TimelineProvider {

    func placeholder(in context: Context) -> N4x4ComplicationEntry {
        N4x4ComplicationEntry(date: Date())
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (N4x4ComplicationEntry) -> Void) {
        completion(N4x4ComplicationEntry(date: Date()))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<N4x4ComplicationEntry>) -> Void) {
        // Static complication — it never needs to refresh.
        completion(Timeline(entries: [N4x4ComplicationEntry(date: Date())], policy: .never))
    }
}

// MARK: - View

struct N4x4ComplicationView: View {
    var entry: N4x4ComplicationEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            switch family {
            case .accessoryCircular:
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.orange)
            case .accessoryCorner:
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.orange)
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    Image(systemName: "bolt.heart.fill")
                        .foregroundStyle(.orange)
                    Text("N4x4")
                        .font(.headline.weight(.bold))
                }
            default:
                Image(systemName: "bolt.heart.fill")
                    .foregroundStyle(.orange)
            }
        }
        .widgetURL(URL(string: "n4x4watch://open"))
    }
}

// MARK: - Widget

struct N4x4Complication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "N4x4Complication",
                            provider: N4x4ComplicationProvider()) { entry in
            N4x4ComplicationView(entry: entry)
        }
        .configurationDisplayName("N4x4 Timer")
        .description("Quick-launch your N4x4 interval session.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular])
    }
}

// MARK: - Entry point
// This @main is for the Widget Extension target. The Watch app target has its
// own @main in N4x4WatchApp.swift — the two must live in separate targets.

@main
struct N4x4ComplicationBundle: WidgetBundle {
    var body: some Widget {
        N4x4Complication()
    }
}
