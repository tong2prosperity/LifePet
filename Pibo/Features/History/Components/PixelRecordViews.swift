import SwiftUI

// The three record cards' pixel pictures (决定 063): the sleep card's night-sky strip, the
// steps card's slope and the activity card's pond. The card keeps its own numbers, ruler
// and legend — only the illustration and the frame join the pixel world, so a recorded
// value never gets re-drawn as an estimate.
//
// Painters live in `Features/Home/Pixel/UI/RecordWindows.swift`; this file only owns the
// clocks, the layout and the tap targets.

// MARK: - Card frame

/// The pixel frame around a record card: square corners, a 2 px ink border and the same
/// hard 3 px shadow the sheets use. The sleep card keeps its dark surface (the night strip
/// draws stars on transparency), the others sit on paper.
struct PixelRecordCard<Content: View>: View {
    var title: String
    var dark = false
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AppLocalization.text(title))
                .font(PixelFont.font(14))
                .foregroundStyle(dark ? Color(pixelHex: 0xC4CBDC) : PixelUIColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if dark {
                LinearGradient(colors: [Color(hex: 0x252B3A), Color(hex: 0x1E2430)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                PixelUIColor.paper
            }
        }
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 2))
        .background(alignment: .bottomTrailing) {
            Rectangle().fill(PixelUIColor.shadow).offset(x: 3, y: 3)
        }
    }
}

// MARK: - Sleep: the night-sky strip

/// The night in sky columns. Tapping picks the interval containing that moment, exactly like
/// the cloud trail it replaces; the cursor is only drawn once something is selected.
struct PixelSleepSkyStrip: View {
    let segments: [SleepSegmentValue]
    let timeline: SleepTrailTimeline
    var selected: SleepSegmentValue?
    var onSelect: (SleepSegmentValue) -> Void

    private var palette: [UInt8] { recordSleepPalette() }

    private var columns: [Int] {
        var slices: [SleepTrailSlice] = []
        for run in SleepTrailGeometry.runs(segments: segments, timeline: timeline,
                                          width: CGFloat(SLEEP_SKY_W)) {
            slices.append(contentsOf: run.slices)
        }
        return sleepSkyColumns(slices: slices)
    }

    private var cursor: Int {
        guard let selected else { return -1 }
        let mid = selected.start.addingTimeInterval(selected.duration / 2)
        let x = timeline.x(of: mid, width: CGFloat(SLEEP_SKY_W))
        return max(0, min(SLEEP_SKY_W - 1, Int(x.rounded(.down))))
    }

    /// The star scatter is seeded by the night itself, so the same sleep keeps the same sky.
    private var seed: Int {
        Int(timeline.start.timeIntervalSince1970 / 60) % 997
    }

    var body: some View {
        GeometryReader { proxy in
            PixelCanvas(logicalWidth: SLEEP_SKY_W, logicalHeight: SLEEP_SKY_H, palette: palette) { frame in
                drawSleepSkyStrip(frame, columns: columns, cursor: cursor, seed: seed)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    guard let segment = SleepTrailGeometry.segment(
                        atX: value.location.x, width: proxy.size.width,
                        segments: segments, timeline: timeline
                    ), segment != selected else { return }
                    onSelect(segment)
                }
            )
        }
        .aspectRatio(CGFloat(SLEEP_SKY_W) / CGFloat(SLEEP_SKY_H), contentMode: .fit)
    }
}

// MARK: - Steps: the slope

/// The day's total grown into a slope: a stone, a sprout, a pine or a tall tree, with Pibo
/// sitting at the top of the grass once the hill has finished growing.
struct PixelStepsSlopeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var steps: Int
    var isToday = true

    @State private var reveal: Double = 0
    @State private var tick = 0

    private var plant: StepsPlant { StepsPlant.forSteps(steps) }

    var body: some View {
        ZStack(alignment: .bottom) {
            PixelCanvas(logicalWidth: STEPS_SLOPE_W, logicalHeight: STEPS_SLOPE_H,
                        revision: tick) { frame in
                drawStepsSlope(frame, plant: plant, reveal: reveal, tick: tick, selected: false)
            }
            Text(AppLocalization.text(isToday ? "今日累计步数" : "当日累计步数"))
                .font(PixelFont.font(11))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(pixelHex: 0x2E3B45, alpha: 0.35))
                .padding(.bottom, 6)
                .allowsHitTesting(false)
        }
        .aspectRatio(CGFloat(STEPS_SLOPE_W) / CGFloat(STEPS_SLOPE_H), contentMode: .fit)
        .onAppear { start() }
        .onChange(of: steps) { _, _ in restart() }
        .task(id: animating) {
            guard animating else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                reveal = min(1, reveal + 0.12)
                tick = (tick + 1) % 1_000_000
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.format(
            "步数，%d 步，%@", steps, AppLocalization.text(isToday ? "今日累计步数" : "当日累计步数")))
    }

    private var animating: Bool { !reduceMotion }

    private func start() {
        if reduceMotion {
            reveal = 1
        } else if reveal < 1 {
            tick += 1
        }
    }

    /// A new day's total grows again from the left; Reduce Motion shows it finished.
    private func restart() {
        reveal = reduceMotion ? 1 : 0
        tick += 1
    }
}

// MARK: - Activity: the pond

/// Core's three intensities as rings and drops. A dry day (or no goals to compare against)
/// leaves the water still — the pond never invents movement.
struct PixelActivityPondView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// [move, exercise, stand] in 0…1, or nil when Core is unavailable.
    var intensities: [Double]?

    @State private var timeSec: Double = 0
    @State private var tick = 0

    private var dry: Bool {
        guard let intensities else { return true }
        return intensities.allSatisfy { $0 < 0.02 }
    }

    private var animating: Bool { !reduceMotion && !dry }

    var body: some View {
        PixelCanvas(logicalWidth: POND_W, logicalHeight: POND_H, revision: tick) { frame in
            drawActivityPond(frame, amps: intensities, timeSec: timeSec, animate: animating)
        }
        .aspectRatio(CGFloat(POND_W) / CGFloat(POND_H), contentMode: .fit)
        .task(id: animating) {
            guard animating else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard !Task.isCancelled else { return }
                timeSec += 0.16
                tick = (tick + 1) % 1_000_000
            }
        }
        .accessibilityHidden(true)
    }
}
