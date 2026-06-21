import SwiftUI

@main
struct ClosePortApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            PortListView(showOpenWindowButton: true)
                .frame(width: 300)
        } label: {
            Image(systemName: "network")
        }
        .menuBarExtraStyle(.window)

        // Ventana standalone ("mini app") que reutiliza la misma vista.
        // Se abre bajo demanda desde el menú; no aparece al iniciar.
        Window("ClosePort", id: "main") {
            PortListView(showOpenWindowButton: false)
                .frame(minWidth: 320, minHeight: 360)
        }
        .windowResizability(.contentSize)
    }
}
