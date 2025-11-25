import Foundation

final class PortService {

    // Apps del sistema que no queremos mostrar
    private let excludedApps: Set<String> = [
        "rapportd", "ControlCe", "Spotify", "Figma", "figma_age",
        "sharingd", "AirPlayXPC", "ScreenTime", "WiFiAgent",
        "identitys", "AMPDeviceD", "Music", "Photos", "Mail",
        "CalendarA", "Reminders", "Notes", "Messages", "FaceTime",
        "Safari", "Preview", "Finder", "SystemUIServer", "Dock",
        "loginwind", "coreaudio", "bluetoot", "WindowServer"
    ]

    // Puertos comunes de desarrollo
    private let devPortRanges: [ClosedRange<Int>] = [
        3000...3999,   // React, Next.js, Rails
        4000...4999,   // Phoenix, Ember
        5000...5999,   // Flask, ControlCenter (filtrado por app)
        5432...5432,   // PostgreSQL
        6379...6379,   // Redis
        8000...8999,   // Django, PHP, general dev
        9000...9999,   // PHP-FPM, SonarQube
        27017...27017, // MongoDB
    ]

    func fetchPorts() -> [Port] {
        let output = runCommand("/usr/sbin/lsof", arguments: ["-iTCP", "-sTCP:LISTEN", "-n", "-P"])
        return parseLsofOutput(output)
    }

    func killProcess(pid: Int) -> Bool {
        // Primero intentar kill normal (SIGTERM - permite cleanup)
        if executeKill(pid: pid, signal: nil) {
            // Esperar un momento y verificar si el proceso murió
            usleep(100_000) // 100ms
            if !isProcessRunning(pid: pid) {
                return true
            }
        }

        // Si sigue vivo, usar kill -9 (SIGKILL - fuerza cierre)
        return executeKill(pid: pid, signal: "-9")
    }

    private func executeKill(pid: Int, signal: String?) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        if let signal = signal {
            process.arguments = [signal, String(pid)]
        } else {
            process.arguments = [String(pid)]
        }
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

    private func isProcessRunning(pid: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-0", String(pid)] // Signal 0 = check if exists
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

            // Filtrar apps del sistema
            if isExcludedApp(command) { continue }

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

            // Solo mostrar puertos de desarrollo (o todos si no está en rangos comunes)
            if !isDevPort(port) { continue }

            guard !seenPorts.contains(port) else { continue }
            seenPorts.insert(port)

            // Formatear address para mostrar "localhost" en vez de "127.0.0.1" o "*"
            let displayAddress = formatAddress(address)

            ports.append(Port(command: command, pid: pid, port: port, address: displayAddress))
        }

        return ports.sorted { $0.port < $1.port }
    }

    private func isExcludedApp(_ command: String) -> Bool {
        for excluded in excludedApps {
            if command.hasPrefix(excluded) { return true }
        }
        return false
    }

    private func isDevPort(_ port: Int) -> Bool {
        // Mostrar puertos en rangos de desarrollo
        for range in devPortRanges {
            if range.contains(port) { return true }
        }
        return false
    }

    private func formatAddress(_ address: String) -> String {
        switch address {
        case "*", "0.0.0.0", "[::]":
            return "0.0.0.0"
        case "127.0.0.1", "[::1]":
            return "localhost"
        default:
            return address
        }
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
