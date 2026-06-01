import Foundation

struct Port: Identifiable, Hashable {
    let command: String
    let pid: Int
    let port: Int
    let address: String

    var id: String { "\(pid):\(port)" }

    var displayName: String {
        "\(command) :\(port)"
    }
}
