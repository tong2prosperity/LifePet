import SwiftUI

struct SessionListView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        List {
            ForEach(store.sessions.sorted { $0.startedAt > $1.startedAt }) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    row(for: session)
                }
            }
        }
        .overlay {
            if store.sessions.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "heart.text.square",
                    description: Text("Start a session on your Apple Watch.")
                )
            }
        }
        .navigationTitle("Sessions")
    }

    private func row(for session: VitalSession) -> some View {
        VStack(alignment: .leading) {
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
            HStack(spacing: 8) {
                Text(session.id.uuidString.prefix(8))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if session.isActive {
                    Text("· live")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Text("· \(store.snapshots(for: session.id).count) snapshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
