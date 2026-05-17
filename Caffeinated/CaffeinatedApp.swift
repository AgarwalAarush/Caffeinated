import SwiftUI

@main
struct CaffeinatedApp: App {
    @StateObject private var manager = CaffeinateManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(manager)
        } label: {
            Image(systemName: manager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
        .menuBarExtraStyle(.window)
    }
}
