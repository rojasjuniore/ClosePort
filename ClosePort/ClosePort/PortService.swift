import Foundation

final class PortService {

    func fetchPorts() -> [Port] {
        let output = runCommand("/usr/sbin/lsof", arguments: ["-iTCP", "-sTCP:LISTEN", "-n", "-P"])
        return parseLsofOutput(output)
    }

    func killProcess(pid: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = [String(pid)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Internal (visible for testing)

    func parseLsofOutput(_ output: String?) -> [Port] {
        guard let output = output, !output.isEmpty else { return [] }

        var ports: [Port] = []
        var seenPorts: Set<Int> = []

        let lines = output.components(separatedBy: "\n")

        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }

            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 9 else { continue }

            let command = String(columns[0])
            guard let pid = Int(columns[1]) else { continue }

            // NAME column is at index 8, but (LISTEN) might be separate
            // Find the column containing ":" which is the address:port
            var nameColumn: String?
            for col in columns.reversed() {
                let colStr = String(col)
                if colStr.contains(":") && !colStr.starts(with: "0x") {
                    nameColumn = colStr
                    break
                }
            }

            guard let name = nameColumn,
                  let (address, port) = parseAddress(name) else { continue }

            guard !seenPorts.contains(port) else { continue }
            seenPorts.insert(port)

            ports.append(Port(command: command, pid: pid, port: port, address: address))
        }

        return ports.sorted { $0.port < $1.port }
    }

    // MARK: - Private

    private func runCommand(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func parseAddress(_ name: String) -> (address: String, port: Int)? {
        let cleaned = name
            .replacingOccurrences(of: "(LISTEN)", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let lastColon = cleaned.lastIndex(of: ":") else { return nil }

        let address = String(cleaned[..<lastColon])
        let portStr = String(cleaned[cleaned.index(after: lastColon)...])

        guard let port = Int(portStr) else { return nil }

        return (address, port)
    }
}
