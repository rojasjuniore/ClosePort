import SwiftUI

struct PortListView: View {
    @State private var ports: [Port] = []
    private let portService = PortService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            Divider()

            if ports.isEmpty {
                emptyStateView
            } else {
                portListView
            }

            Divider()

            footerView
        }
        .frame(width: 280)
        .onAppear { refresh() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Open Ports")
                .font(.headline)

            Spacer()

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    // MARK: - Port List

    private var portListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(ports) { port in
                    PortRow(port: port, onKill: { killPort(port) })

                    if port.id != ports.last?.id {
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
            Text("\(ports.count) port(s)")
                .font(.caption)
                .foregroundStyle(.secondary)

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

    private func refresh() {
        ports = portService.fetchPorts()
    }

    private func killPort(_ port: Port) {
        if portService.killProcess(pid: port.pid) {
            refresh()
        }
    }
}

// MARK: - Port Row

struct PortRow: View {
    let port: Port
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(":\(port.port)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                Text("\(port.command) (PID: \(port.pid))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(port.address)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(action: onKill) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Kill process \(port.pid)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    PortListView()
}
