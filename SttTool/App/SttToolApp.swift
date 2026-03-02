import SwiftUI

@main
struct SttToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            EmptyView()
        } label: {
            EmptyView()
        }
        .menuBarExtraStyle(.window)
    }
}
