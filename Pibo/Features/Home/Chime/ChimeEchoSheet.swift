import PiboCore
import SwiftUI

final class WalkEchoSelectionStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func selectedID(petID: UUID) -> UUID? { defaults.string(forKey: key(petID)).flatMap(UUID.init(uuidString:)) }
    func select(_ id: UUID?, petID: UUID) {
        if let id { defaults.set(id.uuidString.lowercased(), forKey: key(petID)) }
        else { defaults.removeObject(forKey: key(petID)) }
    }
    func validatedSelection(petID: UUID, availableIDs: Set<UUID>) -> UUID? {
        guard let selected = selectedID(petID: petID) else { return nil }
        guard availableIDs.contains(selected) else {
            select(nil, petID: petID)
            return nil
        }
        return selected
    }
    private func key(_ petID: UUID) -> String { "pibo.chime.walkEcho.\(petID.uuidString.lowercased()).v1" }
}

struct ChimeEchoSheet: View {
    let petID: UUID
    let history: HealthHistoryStore
    let onReplay: (WalkDoodleRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    private let selection = WalkEchoSelectionStore()

    init(
        petID: UUID,
        history: HealthHistoryStore,
        onReplay: @escaping (WalkDoodleRecord) -> Void = { _ in }
    ) {
        self.petID = petID
        self.history = history
        self.onReplay = onReplay
        let store = WalkEchoSelectionStore()
        _selectedID = State(initialValue: store.selectedID(petID: petID))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LP.Spacing.l) {
                    Text("风铃记住一条你走过的路线。可以替换，也可以让它安静下来。")
                        .lpText(LP.Typography.b4Regular).foregroundStyle(PiboMoss.Color.secondaryInk)
                    if let chosen = chosenRecord {
                        routeCard(chosen, large: true)
                        Button {
                            onReplay(chosen)
                            dismiss()
                        } label: {
                            Label("在森林重播", systemImage: "play.fill")
                                .lpText(LP.Typography.b4Medium)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PiboMoss.Color.foundationTeal)
                        PiboMossSecondaryButton(title: "清除回声") {
                            selection.select(nil, petID: petID)
                            selectedID = nil
                        }
                    } else {
                        ContentUnavailableView("还没有选中的路线", systemImage: "wind", description: Text("完成一次散步涂鸦后，可以在这里留下回声。"))
                    }
                    if !records.isEmpty {
                        Text(chosenRecord == nil ? "选择路线" : "替换路线")
                            .lpText(LP.Typography.b3Medium).foregroundStyle(PiboMoss.Color.forestInk)
                        ForEach(records, id: \.id) { record in
                            Button {
                                selection.select(record.id, petID: petID)
                                selectedID = record.id
                                LPHaptics.tap()
                            } label: { routeCard(record, large: false) }
                            .buttonStyle(.plain)
                            .accessibilityValue(record.id == selectedID ? "已选择" : "")
                        }
                    }
                }
                .padding(LP.Spacing.xl)
            }
            .background(PiboMoss.Color.sheetMoss.ignoresSafeArea())
            .navigationTitle("风铃回声")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .onAppear {
            selectedID = selection.validatedSelection(
                petID: petID,
                availableIDs: Set(records.map(\.id))
            )
        }
    }

    private var chosenRecord: WalkDoodleRecord? { records.first { $0.id == selectedID } }

    private var records: [WalkDoodleRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<90).flatMap { offset -> [WalkDoodleRecord] in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
            return history.walkDoodles(on: day)
        }.filter(\.hasData).sorted { $0.createdAt > $1.createdAt }
    }

    private func routeCard(_ record: WalkDoodleRecord, large: Bool) -> some View {
        HStack(spacing: LP.Spacing.m) {
            if let shape = record.shape {
                WalkDoodleRouteEchoView(shape: shape, coordinates: record.coordinates)
                    .frame(width: large ? 116 : 74, height: large ? 116 : 74)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title ?? "用脚画下的路").lpText(LP.Typography.b3Medium)
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .lpText(LP.Typography.c1Regular).foregroundStyle(PiboMoss.Color.secondaryInk)
                if let score = record.score { Text("\(score) 分").lpText(LP.Typography.c1Medium).foregroundStyle(PiboMoss.Color.foundationTeal) }
            }
            Spacer()
            if record.id == selectedID { Image(systemName: "checkmark.circle.fill").foregroundStyle(PiboMoss.Color.foundationTeal) }
        }
        .padding(LP.Spacing.m)
        .background(PiboMoss.Color.raisedNeutral.opacity(0.72), in: RoundedRectangle(cornerRadius: PiboMoss.Radius.card))
        .foregroundStyle(PiboMoss.Color.forestInk)
    }
}
