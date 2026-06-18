import SwiftUI
import UserNotifications

struct PortListView: View {
    /// Cuando es true muestra un botón para abrir la ventana standalone.
    /// Lo pasa el MenuBarExtra; la ventana en sí lo deja en false.
    var showOpenWindowButton: Bool = false

    @Environment(\.openWindow) private var openWindow
    @State private var ports: [Port] = []
    @State private var killingPids: Set<Int> = []
    @State private var failedPids: Set<Int> = []
    @State private var searchText: String = ""
    @State private var autoRefreshTimer: Timer?
    @State private var portToConfirmKill: Port?
    @State private var showKillAllConfirm = false
    @AppStorage("showAllPorts") private var showAllPorts = false
    private let portService = PortService()

    private var filteredPorts: [Port] {
        guard !searchText.isEmpty else { return ports }
        let query = searchText.lowercased()
        return ports.filter {
            $0.command.lowercased().contains(query) ||
            String($0.port).contains(query) ||
            String($0.pid).contains(query) ||
            $0.address.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            if !ports.isEmpty {
                searchBar
            }

            Divider()

            if ports.isEmpty {
                emptyStateView
            } else if filteredPorts.isEmpty {
                noResultsView
            } else {
                portListView
            }

            Divider()

            footerView
        }
        .frame(minWidth: 300)
        .onAppear {
            requestNotificationPermission()
            refresh()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .alert("Kill process?", isPresented: Binding(
            get: { portToConfirmKill != nil },
            set: { if !$0 { portToConfirmKill = nil } }
        )) {
            Button("Cancel", role: .cancel) { portToConfirmKill = nil }
            Button("Kill", role: .destructive) {
                if let port = portToConfirmKill {
                    executeKill(port)
                }
                portToConfirmKill = nil
            }
        } message: {
            if let port = portToConfirmKill {
                Text("\(port.command) on port \(port.port) is a critical service. Are you sure?")
            }
        }
        .alert("Kill all ports?", isPresented: $showKillAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Kill All", role: .destructive) { killAllPorts() }
        } message: {
            Text("This will terminate \(filteredPorts.count) process(es).")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Open Ports")
                .font(.headline)

            Spacer()

            if !filteredPorts.isEmpty {
                Button(action: { showKillAllConfirm = true }) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.7))
                .help("Kill all visible ports")
            }

            Button(action: toggleShowAll) {
                Image(systemName: showAllPorts ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.plain)
            .help(showAllPorts ? "Showing all ports — click to show only dev ports" : "Showing only dev ports — click to show all")

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")

            if showOpenWindowButton {
                Button(action: { openWindow(id: "main") }) {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.plain)
                .help("Open in a window")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Filter by port, command, PID...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.title)
                .foregroundStyle(.green)

            Text("No open ports")
                .font(.subheadline)

            Text("All listening ports are closed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
    }

    private var noResultsView: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("No matches for \"\(searchText)\"")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
    }

    // MARK: - Port List

    private var portListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredPorts) { port in
                    PortRow(
                        port: port,
                        isKilling: killingPids.contains(port.pid),
                        hasFailed: failedPids.contains(port.pid),
                        onKill: { killPort(port) }
                    )

                    if port.id != filteredPorts.last?.id {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
        }
        .frame(maxHeight: 300)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if searchText.isEmpty {
                Text("\(ports.count) port(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(filteredPorts.count)/\(ports.count) port(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func toggleShowAll() {
        showAllPorts.toggle()
        refresh()
    }

    private func refresh() {
        ports = portService.fetchPorts(devOnly: !showAllPorts)
        let activePids = Set(ports.map(\.pid))
        killingPids.formIntersection(activePids)
        failedPids.formIntersection(activePids)
    }

    private func killPort(_ port: Port) {
        guard !killingPids.contains(port.pid) else { return }

        if portService.isCriticalProcess(port) {
            portToConfirmKill = port
        } else {
            executeKill(port)
        }
    }

    private func executeKill(_ port: Port) {
        failedPids.remove(port.pid)
        killingPids.insert(port.pid)

        portService.killProcessAsync(pid: port.pid) { success in
            killingPids.remove(port.pid)
            if success {
                sendNotification(
                    title: "Port \(port.port) closed",
                    body: "\(port.command) (PID \(port.pid)) terminated"
                )
                refresh()
            } else {
                failedPids.insert(port.pid)
                sendNotification(
                    title: "Failed to close port \(port.port)",
                    body: "\(port.command) (PID \(port.pid)) could not be killed"
                )
            }
        }
    }

    private func killAllPorts() {
        for port in filteredPorts {
            guard !killingPids.contains(port.pid) else { continue }
            executeKill(port)
        }
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            DispatchQueue.main.async { refresh() }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Port Row

struct PortRow: View {
    let port: Port
    let isKilling: Bool
    let hasFailed: Bool
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(port.address):\(port.port)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text("\(port.command)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if hasFailed {
                        Text("· Failed to kill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            Text("PID \(port.pid)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if isKilling {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            } else {
                Button(action: onKill) {
                    Image(systemName: hasFailed ? "arrow.clockwise.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(hasFailed ? .orange.opacity(0.8) : .red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help(hasFailed ? "Retry kill process \(port.pid)" : "Kill process \(port.pid)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    PortListView()
}
