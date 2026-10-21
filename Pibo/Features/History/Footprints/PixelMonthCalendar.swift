import SwiftUI

/// The footprints' month page (决定 063), in place of the system date picker. A dot says a
/// day has something written, a star that a shared first happened, a ring marks the day you
/// met. Days before the meeting day and after today cannot be opened.
///
/// Ported from HarmonyPibo `pixel/ui/PixelMonthCalendar.ets`.
struct PixelMonthCalendar: View {
    var selected: Date = .now
    var meetingDay: Date = .now
    var today: Date = .now
    var recordedDays: [Date] = []
    var firstDays: [Date] = []
    var onPick: (Date) -> Void = { _ in }
    var onClose: () -> Void = {}

    @State private var year: Int
    @State private var month: Int

    private static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    init(selected: Date = .now, meetingDay: Date = .now, today: Date = .now,
         recordedDays: [Date] = [], firstDays: [Date] = [],
         onPick: @escaping (Date) -> Void = { _ in }, onClose: @escaping () -> Void = {}) {
        self.selected = selected
        self.meetingDay = meetingDay
        self.today = today
        self.recordedDays = recordedDays
        self.firstDays = firstDays
        self.onPick = onPick
        self.onClose = onClose
        let calendar = Calendar.current
        let anchor = selected
        _year = State(initialValue: calendar.component(.year, from: anchor))
        _month = State(initialValue: calendar.component(.month, from: anchor) - 1)
    }

    private var cells: [FootprintsCalendarCell] {
        footprintsCalendar(year: year, month: month, recordedDays: recordedDays,
                           firstDays: firstDays, meetingDay: meetingDay, today: today)
    }

    private func monthIndex(_ year: Int, _ month: Int) -> Int { year * 12 + month }

    private func canTurn(_ delta: Int) -> Bool {
        let target = monthIndex(year, month) + delta
        let calendar = Calendar.current
        let first = min(meetingDay, today)
        let firstIndex = monthIndex(calendar.component(.year, from: first),
                                    calendar.component(.month, from: first) - 1)
        let lastIndex = monthIndex(calendar.component(.year, from: today),
                                   calendar.component(.month, from: today) - 1)
        return target >= firstIndex && target <= lastIndex
    }

    private func turn(_ delta: Int) {
        guard canTurn(delta) else { return }
        let index = monthIndex(year, month) + delta
        year = index / 12
        month = ((index % 12) + 12) % 12
    }

    private func cellLabel(_ cell: FootprintsCalendarCell) -> String {
        var notes: [String] = []
        if cell.meeting { notes.append(AppLocalization.text("相识那天")) }
        if cell.mark == .star {
            notes.append(AppLocalization.text("有共同的第一次"))
        } else if cell.mark == .dot {
            notes.append(AppLocalization.text("有记录"))
        }
        if !cell.enabled { notes.append(AppLocalization.text("不可选")) }
        let date = AppLocalization.format("%@月%@日", "\(month + 1)", "\(cell.date)")
        return notes.isEmpty ? date : "\(date)，\(notes.joined(separator: "，"))"
    }

    var body: some View {
        VStack(spacing: 10) {
            PixelSheetTitle(title: "翻到哪一天", onClose: onClose)
            HStack {
                turnButton(-1)
                Text(AppLocalization.format("%@年%@月", "\(year)", "\(month + 1)"))
                    .font(PixelFont.font(15))
                    .foregroundStyle(PixelUIColor.ink)
                    .frame(maxWidth: .infinity)
                turnButton(1)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { name in
                    Text(AppLocalization.text(name))
                        .font(PixelFont.font(12))
                        .foregroundStyle(PixelUIColor.inkSoft)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                      spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    dayCell(cell)
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Rectangle().fill(PixelUIColor.leaf).frame(width: 4, height: 4)
                    Text(AppLocalization.text("有记录")).font(.system(size: 11))
                        .foregroundStyle(PixelUIColor.inkSoft)
                }
                HStack(spacing: 4) {
                    PixelIcon(rows: PixelIcons.star, iconSize: 8)
                    Text(AppLocalization.text("共同的第一次")).font(.system(size: 11))
                        .foregroundStyle(PixelUIColor.inkSoft)
                }
                HStack(spacing: 4) {
                    Rectangle().strokeBorder(PixelUIColor.heart, lineWidth: 2)
                        .frame(width: 10, height: 10)
                    Text(AppLocalization.text("相识那天")).font(.system(size: 11))
                        .foregroundStyle(PixelUIColor.inkSoft)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
        .padding(14)
        .frame(width: 340)
        .background(PixelUIColor.paper)
        .overlay(Rectangle().strokeBorder(PixelUIColor.border, lineWidth: 3))
        .background(alignment: .bottomTrailing) {
            Rectangle().fill(PixelUIColor.shadow).offset(x: 4, y: 4)
        }
        .accessibilityIdentifier("pixel-month-calendar")
    }

    private func turnButton(_ delta: Int) -> some View {
        Text(delta < 0 ? "‹" : "›")
            .font(PixelFont.font(20))
            .foregroundStyle(canTurn(delta) ? PixelUIColor.ink : PixelUIColor.off)
            .frame(width: 44, height: 44)
            .background(PixelUIColor.paperDim)
            .overlay(Rectangle().strokeBorder(
                canTurn(delta) ? PixelUIColor.border : PixelUIColor.off, lineWidth: 2))
            .contentShape(Rectangle())
            .onTapGesture { turn(delta) }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(AppLocalization.text(delta < 0 ? "上个月" : "下个月"))
    }

    @ViewBuilder
    private func dayCell(_ cell: FootprintsCalendarCell) -> some View {
        if let day = cell.day {
            let isSelected = Calendar.current.startOfDay(for: selected) == day
            ZStack(alignment: .top) {
                Text("\(cell.date)")
                    .font(PixelFont.font(12))
                    .foregroundStyle(isSelected ? PixelUIColor.paper
                                     : (cell.enabled ? PixelUIColor.ink : PixelUIColor.off))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                if cell.today {
                    Rectangle()
                        .fill(PixelUIColor.gold)
                        .frame(width: 18, height: 2)
                        .padding(.top, 3)
                }
                if cell.mark == .star {
                    PixelIcon(rows: PixelIcons.star, iconSize: 8)
                        .padding(.top, 31)
                } else if cell.mark == .dot {
                    Rectangle()
                        .fill(PixelUIColor.leaf)
                        .frame(width: 4, height: 4)
                        .padding(.top, 35)
                }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(isSelected ? PixelUIColor.ink : Color.clear)
            .overlay {
                if cell.meeting {
                    Rectangle().strokeBorder(PixelUIColor.heart, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard cell.enabled else { return }
                onPick(day)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(cellLabel(cell))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            Color.clear.frame(height: 44).frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }
}
