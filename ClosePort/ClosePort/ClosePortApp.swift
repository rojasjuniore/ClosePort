import SwiftUI

@main
struct ClosePortApp: App {
    var body: some Scene {
        MenuBarExtra {
            PortListView()
        } label: {
            Image(systemName: "network")
        }
        .menuBarExtraStyle(.window)
    }
}
