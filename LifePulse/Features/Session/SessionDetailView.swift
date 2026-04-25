import SwiftUI

struct SessionDetailView: View {
    let session: VitalSession
    @Environment(SessionStore.self) private var store

    var body: some View {
        let latest = store.latestSnapshot(for: session.id)

        List {
            Section("Session") {
                LabeledContent("ID", value: session.id.uuidString)
                LabeledContent("Started", value: session.startedAt.formatted())
                if let endedAt = session.endedAt {
                    LabeledContent("Ended", value: endedAt.formatted())
                } else {
                    LabeledContent("State", value: "live")
                }
            }

            Section("Latest vitals") {
                LabeledContent("HR", value: format(latest?.first(of: .heartRate)?.value, suffix: "bpm"))
                LabeledContent("SpO₂", value: format(latest?.first(of: .spo2)?.value, suffix: "%"))
                LabeledContent("HRV", value: format(latest?.first(of: .hrv)?.value, suffix: "ms"))
            }

            Section("Data") {
                LabeledContent("Snapshots", value: "\(store.snapshots(for: session.id).count)")
            }
        }
        .navigationTitle("Session")
    }

    private func format(_ v: Double?, suffix: String) -> String {
        guard let v else { return "--" }
        return "\(Int(v)) \(suffix)"
    }
}
