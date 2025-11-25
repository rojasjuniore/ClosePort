import Foundation

struct Port: Identifiable, Hashable {
    let id = UUID()
    let command: String
    let pid: Int
    let port: Int
    let address: String

    var displayName: String {
        "\(command) :\(port)"
    }
}
