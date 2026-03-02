import SwiftUI

struct MenuBarView: View {
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("SttTool")
                .font(.headline)
            Text("Loading...")
                .foregroundStyle(.secondary)
            Divider()
            Button("Settings...") { onOpenSettings() }
            Button("Quit") { onQuit() }
        }
        .padding()
    }
}
