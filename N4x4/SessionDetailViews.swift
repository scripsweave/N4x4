// SessionDetailViews.swift
// The reimagined post-workout experience and its history twin:
//   • SessionStripChart — the full-session heart-rate chart: shaded target
//     bands per interval, the actual HR line coloured by zone status (the
//     same orange/red/green language as the live UI), boundary rules.
//   • IntervalPager — swipeable per-interval cards: zoomed chart, time-in-zone
//     ring, avg/peak, time-to-zone, ghost overlay of the previous session,
//     and (in the post-workout flow) the performance value + note fields.
//   • PostWorkoutSummaryRedesignView — replaces the stock Form summary.
//   • SessionDetailSheet — the same experience for a saved history entry.
//   • ShareCardView + renderer — a shareable image of the session.
// All colours come from Palette (HomeWorkoutRedesign.swift).

import SwiftUI
import Charts

// MARK: - Time formatting

private func mmss(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Chart model

/// Consecutive samples sharing one zone colour, pre-split so Swift Charts can
/// draw a multi-coloured line as separate series. Boundary samples are
/// duplicated into the next segment so the line stays visually continuous;
/// gaps > 15 s (pauses) genuinely break the line.
struct HRZoneSegment: Identifiable {
    let id: Int
    let color: Color
    let samples: [HeartRateSeries.Sample]
}

enum SessionChartModel {

    static func bandColor(_ kind: String) -> Color {
        switch kind {
        case HeartRateSeries.IntervalSpan.kindWork:     return Palette.amber
        case HeartRateSeries.IntervalSpan.kindRecovery: return Palette.electricBlue
        default:                                        return Palette.textTertiary
        }
    }

    static func spanTitle(_ span: HeartRateSeries.IntervalSpan) -> String {
        switch span.kind {
        case HeartRateSeries.IntervalSpan.kindWork:     return "WORK \(span.workNumber)"
        case HeartRateSeries.IntervalSpan.kindRecovery: return "RECOVERY"
        case HeartRateSeries.IntervalSpan.kindWarmup:   return "WARM UP"
        default:                                        return "COOL DOWN"
        }
    }

    static func zoneColor(for sample: HeartRateSeries.Sample,
                          in series: HeartRateSeries) -> Color {
        guard let span = series.spans.first(where: { sample.t >= $0.start && sample.t <= $0.end }),
              span.hasTarget else {
            return Palette.textPrimary.opacity(0.85)
        }
        if Int(sample.bpm) < span.targetLo { return .orange }
        if Int(sample.bpm) > span.targetHi { return Palette.danger }
        return Palette.recovery
    }

    static func segments(for series: HeartRateSeries,
                         in range: ClosedRange<Double>? = nil) -> [HRZoneSegment] {
        var samples = series.samples
        if let range {
            samples = samples.filter { range.contains($0.t) }
        }
        guard !samples.isEmpty else { return [] }

        var out: [HRZoneSegment] = []
        var current: [HeartRateSeries.Sample] = [samples[0]]
        var currentColor = zoneColor(for: samples[0], in: series)

        for sample in samples.dropFirst() {
            let color = zoneColor(for: sample, in: series)
            let gap = sample.t - (current.last?.t ?? sample.t)
            if gap > 15 {
                out.append(HRZoneSegment(id: out.count, color: currentColor, samples: current))
                current = [sample]
                currentColor = color
            } else if color != currentColor {
                out.append(HRZoneSegment(id: out.count, color: currentColor, samples: current))
                // Re-use the boundary sample so the line has no visual break.
                current = [current.last!, sample]
                currentColor = color
            } else {
                current.append(sample)
            }
        }
        out.append(HRZoneSegment(id: out.count, color: currentColor, samples: current))
        return out
    }

    /// Y-axis domain padded around both the samples and every target band.
    static func yDomain(for series: HeartRateSeries) -> ClosedRange<Int> {
        var lo = series.samples.map(\.bpm).min().map(Int.init) ?? 60
        var hi = series.samples.map(\.bpm).max().map(Int.init) ?? 180
        for span in series.spans where span.hasTarget {
            lo = min(lo, span.targetLo)
            hi = max(hi, span.targetHi)
        }
        return max(30, lo - 8)...(hi + 8)
    }
}

// MARK: - Full-session strip chart

struct SessionStripChart: View {
    let series: HeartRateSeries
    var height: CGFloat = 190
    var showsAxes: Bool = true

    private var duration: Double { series.samples.last?.t ?? series.spans.last?.end ?? 60 }

    var body: some View {
        Chart {
            ForEach(series.spans.filter(\.hasTarget), id: \.start) { span in
                RectangleMark(
                    xStart: .value("Start", span.start),
                    xEnd: .value("End", span.end),
                    yStart: .value("Lo", span.targetLo),
                    yEnd: .value("Hi", span.targetHi)
                )
                .foregroundStyle(SessionChartModel.bandColor(span.kind).opacity(0.16))
            }

            ForEach(series.spans.dropFirst(), id: \.start) { span in
                RuleMark(x: .value("Boundary", span.start))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Palette.hairline)
            }

            ForEach(SessionChartModel.segments(for: series)) { segment in
                ForEach(Array(segment.samples.enumerated()), id: \.offset) { _, sample in
                    LineMark(
                        x: .value("Time", sample.t),
                        y: .value("BPM", sample.bpm),
                        series: .value("Segment", "seg\(segment.id)")
                    )
                    .foregroundStyle(segment.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
            }
        }
        .chartXScale(domain: 0...max(duration, 60))
        .chartYScale(domain: SessionChartModel.yDomain(for: series))
        .chartXAxis {
            if showsAxes {
                AxisMarks(values: .stride(by: max(120, (duration / 5).rounded()))) { value in
                    AxisGridLine().foregroundStyle(Palette.hairline)
                    AxisValueLabel {
                        if let t = value.as(Double.self) {
                            Text(mmss(t))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if showsAxes {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Palette.hairline)
                    AxisValueLabel {
                        if let bpm = value.as(Int.self) {
                            Text("\(bpm)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Tiny sparkline (history rows)

struct HRSparklineView: View {
    let points: [Int]
    var tint: Color = Palette.electricBlue

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { index, bpm in
            LineMark(x: .value("i", index), y: .value("bpm", bpm))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
    }

    /// Padded so a flat line never produces a zero-height domain.
    private var yDomain: ClosedRange<Int> {
        let lo = points.min() ?? 60
        let hi = points.max() ?? 180
        return (lo - 5)...(hi + 5)
    }
}

// MARK: - In-zone ring

struct InZoneRing: View {
    let pct: Int
    var size: CGFloat = 52

    private var color: Color {
        switch pct {
        case 75...: return Palette.recovery
        case 45...: return Palette.amber
        default:    return Palette.danger
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, pct))) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(pct)%")
                    .font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text("ZONE")
                    .font(.system(size: size * 0.13, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Interval pager

/// Swipeable per-interval cards. `editableWorkFields` switches on the
/// performance/notes editors (post-workout flow only).
struct IntervalPager: View {
    let series: HeartRateSeries
    /// The previous comparable session, drawn as a dashed ghost on work cards.
    var ghost: HeartRateSeries?
    var editableWorkFields: Bool = false
    /// Read-only saved performances (history flow).
    var savedPerformances: [IntervalPerformance]? = nil
    var modality: TrainingModality? = nil
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        TabView {
            ForEach(Array(series.spans.enumerated()), id: \.offset) { _, span in
                IntervalCard(series: series, span: span,
                             ghostSpanSamples: ghostSamples(for: span),
                             editableWorkFields: editableWorkFields,
                             savedPerformance: savedPerformance(for: span),
                             modality: modality,
                             viewModel: viewModel)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 30) // page dots
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: editableWorkFields ? 400 : 330)
    }

    /// The matching work interval from the ghost session, time-shifted onto
    /// this span's x-range so the two curves overlay.
    private func ghostSamples(for span: HeartRateSeries.IntervalSpan) -> [HeartRateSeries.Sample]? {
        guard span.kind == HeartRateSeries.IntervalSpan.kindWork,
              let ghost,
              let ghostSpan = ghost.spans.first(where: {
                  $0.kind == HeartRateSeries.IntervalSpan.kindWork && $0.workNumber == span.workNumber
              }) else { return nil }
        return ghost.samples(in: ghostSpan).map {
            .init(t: $0.t - ghostSpan.start + span.start, bpm: $0.bpm)
        }
    }

    private func savedPerformance(for span: HeartRateSeries.IntervalSpan) -> IntervalPerformance? {
        guard span.kind == HeartRateSeries.IntervalSpan.kindWork else { return nil }
        return savedPerformances?.first { $0.intervalNumber == span.workNumber }
    }
}

struct IntervalCard: View {
    let series: HeartRateSeries
    let span: HeartRateSeries.IntervalSpan
    let ghostSpanSamples: [HeartRateSeries.Sample]?
    let editableWorkFields: Bool
    let savedPerformance: IntervalPerformance?
    let modality: TrainingModality?
    @ObservedObject var viewModel: TimerViewModel

    private var spanSamples: [HeartRateSeries.Sample] { series.samples(in: span) }
    private var avgBPM: Int? {
        let b = spanSamples.map(\.bpm)
        return b.isEmpty ? nil : Int((b.reduce(0, +) / Double(b.count)).rounded())
    }
    private var peakBPM: Int? { spanSamples.map(\.bpm).max().map { Int($0.rounded()) } }
    private var inZone: Int? { HeartRateSeriesAnalytics.inZonePct(series, span: span) }
    private var timeToZone: Double? {
        span.kind == HeartRateSeries.IntervalSpan.kindWork
            ? HeartRateSeriesAnalytics.timeToZone(series, span: span) : nil
    }
    private var accent: Color { SessionChartModel.bandColor(span.kind) }
    /// 1-based index into the performance drafts for editable work cards.
    private var draftIndex: Int? {
        guard editableWorkFields, span.kind == HeartRateSeries.IntervalSpan.kindWork,
              viewModel.performanceDraft.indices.contains(span.workNumber - 1) else { return nil }
        return span.workNumber - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(SessionChartModel.spanTitle(span))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(accent)
                    .tracking(1)
                Spacer()
                if span.hasTarget {
                    Text("TARGET \(span.targetLo)–\(span.targetHi)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .tracking(0.5)
                }
            }

            intervalChart

            HStack(spacing: 14) {
                if let inZone {
                    InZoneRing(pct: inZone)
                }
                if let avgBPM {
                    stat("AVG", "\(avgBPM)")
                }
                if let peakBPM {
                    stat("PEAK", "\(peakBPM)")
                }
                if let timeToZone {
                    stat("TO ZONE", mmss(timeToZone))
                }
                if ghostSpanSamples != nil {
                    stat("GHOST", "last", tint: Palette.textTertiary)
                }
                Spacer()
            }

            if let index = draftIndex {
                editorFields(index: index)
            } else if let saved = savedPerformance {
                savedFields(saved)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
    }

    private var intervalChart: some View {
        Chart {
            if span.hasTarget {
                RectangleMark(
                    xStart: .value("Start", span.start),
                    xEnd: .value("End", span.end),
                    yStart: .value("Lo", span.targetLo),
                    yEnd: .value("Hi", span.targetHi)
                )
                .foregroundStyle(accent.opacity(0.16))
            }
            if let ghostSpanSamples {
                ForEach(Array(ghostSpanSamples.enumerated()), id: \.offset) { _, s in
                    LineMark(x: .value("Time", s.t), y: .value("BPM", s.bpm),
                             series: .value("Segment", "ghost"))
                        .foregroundStyle(Palette.textTertiary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .interpolationMethod(.monotone)
                }
            }
            ForEach(SessionChartModel.segments(for: series, in: span.start...span.end)) { segment in
                ForEach(Array(segment.samples.enumerated()), id: \.offset) { _, sample in
                    LineMark(x: .value("Time", sample.t), y: .value("BPM", sample.bpm),
                             series: .value("Segment", "seg\(segment.id)"))
                        .foregroundStyle(segment.color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartXScale(domain: span.start...max(span.end, span.start + 30))
        .chartYScale(domain: SessionChartModel.yDomain(for: series))
        .chartXAxis {
            AxisMarks(values: .stride(by: max(60, (span.duration / 3).rounded()))) { value in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel {
                    if let t = value.as(Double.self) {
                        Text(mmss(t - span.start))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel {
                    if let bpm = value.as(Int.self) {
                        Text("\(bpm)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
        .frame(height: 130)
    }

    private func stat(_ label: String, _ value: String, tint: Color = Palette.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.textTertiary)
                .tracking(0.5)
        }
    }

    @ViewBuilder
    private func editorFields(index: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(viewModel.currentPerformanceMetric.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                TextField("—", value: Binding(
                    get: { viewModel.performanceDraft[index] },
                    set: { viewModel.performanceDraft[index] = $0 }
                ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 76)
                    .foregroundStyle(Palette.textPrimary)
                Text(viewModel.currentPerformanceUnit)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            }
            TextField("Note — settings, how it felt…", text: Binding(
                get: {
                    viewModel.performanceNotesDraft.indices.contains(index)
                        ? viewModel.performanceNotesDraft[index] : ""
                },
                set: {
                    if viewModel.performanceNotesDraft.indices.contains(index) {
                        viewModel.performanceNotesDraft[index] = $0
                    }
                }
            ))
            .font(.system(size: 13))
            .foregroundStyle(Palette.textPrimary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceRaised))
    }

    @ViewBuilder
    private func savedFields(_ saved: IntervalPerformance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let value = saved.primary, let modality {
                let metric = modality.performanceMetric
                let unit = (metric.localeConverted && viewModel.usesImperialUnits)
                    ? (metric.imperialUnit ?? metric.unit) : metric.unit
                let display = viewModel.displayValue(value, for: modality)
                HStack {
                    Text(metric.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("\(display, specifier: "%.1f") \(unit)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            if let note = saved.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceRaised))
    }
}

// MARK: - Hero stats strip

struct SessionHeroStats: View {
    let duration: String
    let avg: Int?
    let max: Int?
    let inZonePct: Int?

    var body: some View {
        HStack(spacing: 10) {
            chip(icon: "clock.fill", value: duration, label: "TOTAL", tint: Palette.electricBlue)
            if let avg { chip(icon: "heart.fill", value: "\(avg)", label: "AVG BPM", tint: Palette.recovery) }
            if let max { chip(icon: "flame.fill", value: "\(max)", label: "PEAK", tint: Palette.danger) }
            if let inZonePct { chip(icon: "target", value: "\(inZonePct)%", label: "IN ZONE", tint: Palette.amber) }
        }
    }

    private func chip(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Palette.textTertiary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
    }
}

// MARK: - Share card

struct ShareCardView: View {
    let series: HeartRateSeries
    let title: String
    let dateText: String
    let duration: String
    let summary: HRSessionSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("N4X4")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                        .tracking(2)
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.electricBlue)
                        .tracking(1)
                }
                Spacer()
                Text(dateText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }

            SessionStripChart(series: series, height: 170)

            HStack(spacing: 18) {
                shareStat(duration, "TOTAL")
                if let summary {
                    shareStat("\(summary.avgBPM)", "AVG BPM")
                    shareStat("\(summary.maxBPM)", "PEAK")
                    if let z = summary.workInZonePct { shareStat("\(z)%", "IN ZONE") }
                }
                Spacer()
            }
        }
        .padding(22)
        .frame(width: 380)
        .background(Palette.background)
    }

    private func shareStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.textTertiary)
                .tracking(0.5)
        }
    }
}

@MainActor
func renderShareCard(series: HeartRateSeries, title: String, dateText: String,
                     duration: String, summary: HRSessionSummary?) -> UIImage? {
    let renderer = ImageRenderer(content: ShareCardView(
        series: series, title: title, dateText: dateText,
        duration: duration, summary: summary))
    renderer.scale = 3
    return renderer.uiImage
}

// MARK: - Post-workout summary (redesigned)

struct PostWorkoutSummaryRedesignView: View {
    @ObservedObject var viewModel: TimerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var ghost: HeartRateSeries?
    @State private var shareImage: UIImage?

    private var series: HeartRateSeries? { viewModel.completedSeries }
    private var summary: HRSessionSummary? {
        series.flatMap(HeartRateSeriesAnalytics.summary(for:))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero

                    workoutTypeSection

                    if let series {
                        sectionTitle("SESSION")
                        SessionStripChart(series: series)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.hairline, lineWidth: 1))

                        sectionTitle("INTERVALS — swipe, log your settings")
                        IntervalPager(series: series, ghost: ghost,
                                      editableWorkFields: true,
                                      viewModel: viewModel)
                    } else {
                        noSeriesNote
                    }

                    logSection
                }
                .padding(18)
                .padding(.bottom, 28)
            }
            .background(Palette.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle("Workout Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        viewModel.closePostWorkoutSummaryWithoutSaving()
                        dismiss()
                    }
                    .foregroundStyle(Palette.danger)
                }
                ToolbarItem(placement: .primaryAction) {
                    if let image = shareImage {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("N4x4 Session", image: Image(uiImage: image))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.saveWorkoutLogEntryAndResetSession()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                viewModel.preparePerformanceDraft()
                loadGhost()
                prepareShareImage()
            }
            .onChange(of: viewModel.selectedWorkoutType) { _, _ in
                viewModel.preparePerformanceDraft()
                loadGhost()
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Palette.recovery)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Norwegian 4×4 complete")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text(Date.now, style: .date)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
            }
            SessionHeroStats(
                duration: durationText,
                avg: summary?.avgBPM,
                max: summary?.maxBPM,
                inZonePct: summary?.workInZonePct
            )
        }
    }

    private var durationText: String {
        mmss(viewModel.currentSessionBreakdown.totalDuration)
    }

    private var noSeriesNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.slash")
                .foregroundStyle(Palette.textTertiary)
            Text("No heart-rate stream this session — connect an Apple Watch, Garmin, or WHOOP to get interval charts here.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
    }

    private var workoutTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("WORKOUT TYPE")
            HStack {
                Text("Type")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Picker("Type", selection: $viewModel.selectedWorkoutType) {
                    ForEach(WorkoutType.selectableCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .tint(Palette.electricBlue)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("NOTES")
            TextField("Session notes (optional)", text: $viewModel.workoutNotesDraft, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 14))
                .foregroundStyle(Palette.textPrimary)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.textSecondary)
            .tracking(1)
    }

    /// The most recent saved session on the same modality that has a series —
    /// its work intervals become dashed ghost lines for comparison.
    private func loadGhost() {
        let modality = viewModel.selectedWorkoutType.trainingModality
        guard let previous = viewModel.workoutLogEntries.first(where: {
            $0.modality == modality && $0.hrSummary != nil
        }) else {
            ghost = nil
            return
        }
        ghost = HeartRateSeriesStore.load(for: previous.id)
    }

    private func prepareShareImage() {
        guard let series else { return }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        shareImage = renderShareCard(
            series: series,
            title: viewModel.selectedWorkoutType.rawValue,
            dateText: formatter.string(from: Date()),
            duration: durationText,
            summary: summary
        )
    }
}

// MARK: - History detail

/// Full session detail for a saved history entry — same visual system as the
/// post-workout summary, read-only.
struct SessionDetailSheet: View {
    let entry: WorkoutLogEntry
    @ObservedObject var viewModel: TimerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var series: HeartRateSeries?
    @State private var ghost: HeartRateSeries?
    @State private var shareImage: UIImage?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SessionHeroStats(
                        duration: mmss(entry.sessionBreakdown?.totalDuration ?? 0),
                        avg: entry.hrSummary?.avgBPM,
                        max: entry.hrSummary?.maxBPM,
                        inZonePct: entry.hrSummary?.workInZonePct
                    )

                    if let series {
                        sectionTitle("SESSION")
                        SessionStripChart(series: series)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.hairline, lineWidth: 1))

                        sectionTitle("INTERVALS")
                        IntervalPager(series: series, ghost: ghost,
                                      savedPerformances: entry.intervalPerformances,
                                      modality: entry.modality,
                                      viewModel: viewModel)
                    } else if entry.hrSummary == nil {
                        Text("No heart-rate data was recorded for this session.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                    }

                    if !entry.notes.isEmpty {
                        sectionTitle("NOTES")
                        Text(entry.notes)
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.textSecondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
                    }
                }
                .padding(18)
                .padding(.bottom, 28)
            }
            .background(Palette.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle(entry.completedAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let image = shareImage {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview("N4x4 Session", image: Image(uiImage: image))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { load() }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.textSecondary)
            .tracking(1)
    }

    private func load() {
        series = HeartRateSeriesStore.load(for: entry.id)
        // Ghost: the session on the same modality immediately older than this one.
        if let modality = entry.modality,
           let previous = viewModel.workoutLogEntries.first(where: {
               $0.id != entry.id && $0.modality == modality
                   && $0.hrSummary != nil && $0.completedAt < entry.completedAt
           }) {
            ghost = HeartRateSeriesStore.load(for: previous.id)
        }
        if let series {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            shareImage = renderShareCard(
                series: series,
                title: entry.workoutType.rawValue,
                dateText: formatter.string(from: entry.completedAt),
                duration: mmss(entry.sessionBreakdown?.totalDuration ?? 0),
                summary: entry.hrSummary
            )
        }
    }
}
