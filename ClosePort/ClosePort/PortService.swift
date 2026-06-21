import Foundation

/// Clave de deduplicación: un mismo proceso (pid) en un mismo puerto
/// es una sola entrada, sin importar si escucha en IPv4 e IPv6.
private struct PortKey: Hashable {
    let pid: Int
    let port: Int
}

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

    // Servicios críticos que requieren confirmación antes de matar
    private let criticalCommands: Set<String> = [
        "postgres", "redis-ser", "mongod", "mysqld", "mariadbd"
    ]

    // Puertos comunes de desarrollo
    private let devPortRanges: [ClosedRange<Int>] = [
        3000...3999,   // React, Next.js, Rails
        3306...3306,   // MySQL
        3307...3307,   // MariaDB
        4000...4999,   // Phoenix, Ember
        5000...5999,   // Flask, ControlCenter (filtrado por app)
        5432...5432,   // PostgreSQL
        6379...6379,   // Redis
        8000...8999,   // Django, PHP, general dev
        9000...9999,   // PHP-FPM, SonarQube
        27017...27017, // MongoDB
    ]

    func fetchPorts(devOnly: Bool = true) -> [Port] {
        let output = runCommand("/usr/sbin/lsof", arguments: ["-iTCP", "-sTCP:LISTEN", "-n", "-P"])
        return parseLsofOutput(output, devOnly: devOnly)
    }

    /// Mata el proceso de forma asíncrona con reintentos y verificación.
    /// Llama a `onResult` en el main thread con `true` si se mató exitosamente.
    func killProcessAsync(pid: Int, onResult: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // 1. SIGTERM
            _ = executeKill(pid: pid, signal: nil)

            // 2. Verificar con reintentos (hasta 500ms)
            for _ in 0..<5 {
                usleep(100_000) // 100ms
                if !isProcessRunning(pid: pid) {
                    DispatchQueue.main.async { onResult(true) }
                    return
                }
            }

            // 3. SIGKILL si sigue vivo
            _ = executeKill(pid: pid, signal: "-9")

            // 4. Verificar después de SIGKILL (hasta 300ms más)
            for _ in 0..<3 {
                usleep(100_000)
                if !isProcessRunning(pid: pid) {
                    DispatchQueue.main.async { onResult(true) }
                    return
                }
            }

            // 5. No se pudo matar
            DispatchQueue.main.async { onResult(false) }
        }
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

    func parseLsofOutput(_ output: String?, devOnly: Bool = true) -> [Port] {
        guard let output = output, !output.isEmpty else { return [] }

        var ports: [Port] = []
        // Dedup por (pid, port): un mismo proceso en IPv4+IPv6 es una sola fila,
        // pero dos procesos distintos en el mismo puerto se muestran ambos.
        var seen: [PortKey: Int] = [:] // PortKey -> índice en `ports`

        let lines = output.components(separatedBy: "\n")

        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }

            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            // Necesitamos al menos COMMAND, PID y la columna NAME (con ":").
            guard columns.count >= 3 else { continue }

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

            // Solo mostrar puertos de desarrollo cuando devOnly está activo
            if devOnly && !isDevPort(port) { continue }

            // Formatear address para mostrar "localhost" en vez de "127.0.0.1" o "*"
            let displayAddress = formatAddress(address)

            let key = PortKey(pid: pid, port: port)
            if let existingIndex = seen[key] {
                // Mismo proceso, mismo puerto (típicamente IPv4 + IPv6):
                // decidir qué dirección conservar para la fila ya existente.
                let existing = ports[existingIndex]
                ports[existingIndex] = Port(
                    command: command,
                    pid: pid,
                    port: port,
                    address: preferredAddress(existing: existing.address, candidate: displayAddress)
                )
            } else {
                seen[key] = ports.count
                ports.append(Port(command: command, pid: pid, port: port, address: displayAddress))
            }
        }

        return ports.sorted { $0.port < $1.port }
    }

    func isExcludedApp(_ command: String) -> Bool {
        for excluded in excludedApps {
            if command.hasPrefix(excluded) { return true }
        }
        return false
    }

    func isDevPort(_ port: Int) -> Bool {
        // Mostrar puertos en rangos de desarrollo
        for range in devPortRanges {
            if range.contains(port) { return true }
        }
        return false
    }

    func isCriticalProcess(_ port: Port) -> Bool {
        let cmd = port.command.lowercased()
        return criticalCommands.contains(where: { cmd.hasPrefix($0) })
    }

    /// Decide qué dirección mostrar cuando un mismo proceso escucha el mismo
    /// puerto en IPv4 e IPv6 (ej: "localhost" via 127.0.0.1 y via [::1], o
    /// "0.0.0.0" via * y "localhost" via [::1]).
    ///
    /// `existing` es la dirección ya guardada; `candidate` la nueva línea.
    /// Devuelve la que debe quedar visible en la fila.
    ///
    /// Prioridad: 0.0.0.0 (expuesto a toda la red) > IP específica > localhost.
    /// En una herramienta de puertos, saber que algo escucha en todas las
    /// interfaces es la info más relevante, así que esa dirección gana.
    func preferredAddress(existing: String, candidate: String) -> String {
        let rank: (String) -> Int = { addr in
            switch addr {
            case "0.0.0.0": return 2
            case "localhost": return 0
            default: return 1
            }
        }
        return rank(candidate) > rank(existing) ? candidate : existing
    }

    func formatAddress(_ address: String) -> String {
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
