//
//  ContainersListDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

struct ContainersListDetailView: View {
    @ObservedObject var state = DockerManagerState.shared
    let engine: ContainerEngine

    @State private var containerOutputToView: ContainerInfo? = nil
    @State private var showingOutput = false

    private var containers: [ContainerInfo] { state.manager.containers(for: engine) }
    private var discovered: [ContainerConfig] { state.manager.discovered[engine] ?? [] }
    private var isScanning: Bool { state.manager.scanning.contains(engine) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ModuleDetailHeader(
                title: "\(engine.hostName) Containers",
                actionButtons: {
                    HStack(spacing: 8) {
                        VariantButton("Add Container", icon: "plus", variant: .primary) {
                            state.showingAddContainer = true
                        }

                        VariantButton("Scan", icon: "magnifyingglass", variant: .secondary, isLoading: isScanning) {
                            Task { await state.manager.scan(engine) }
                        }
                        .disabled(isScanning || !state.isRunning(engine))

                        VariantButton(icon: "arrow.clockwise", variant: .secondary, tooltip: "Refresh") {
                            Task { await refresh() }
                        }
                    }
                }
            )

            Divider()

            if !state.isRunning(engine) {
                EngineStoppedView(host: state.engineRuntime(engine))
            } else if showingOutput,
               let containerInfo = containerOutputToView,
               let runtime = state.manager.getRuntime(id: containerInfo.id) {
                // Output panel with custom title
                CommandOutputView(dataSource: runtime) {
                    Button(action: {
                        showingOutput = false
                        containerOutputToView = nil
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.caption)
                            Text("\(containerInfo.name) Output")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                if !discovered.isEmpty {
                    discoveredSection
                }
                if containers.isEmpty {
                    emptyState
                } else {
                    containersTable
                }
            }
        }
        .task {
            await refresh()
        }
        .onChange(of: state.isRunning(engine)) { _, running in
            if running { Task { await refresh() } }
        }
    }

    private func refresh() async {
        await state.manager.refreshContainersList()
        await state.manager.scan(engine)
    }

    // MARK: - Found outside DevDash

    private var discoveredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Found outside DevDash (\(discovered.count))", systemImage: "sparkle.magnifyingglass")
                    .font(.headline)
                Spacer()
                if discovered.count > 1 {
                    VariantButton("Add All", icon: "plus", variant: .primary) {
                        state.manager.adopt(discovered)
                    }
                }
            }
            ForEach(discovered) { config in
                HStack(spacing: 12) {
                    Text(config.name).font(.body.monospaced())
                    Text(config.image).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    if !config.ports.isEmpty {
                        Text(config.ports.map(\.dockerFormat).joined(separator: ", "))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    VariantButton("Add", icon: "plus", variant: .secondary) {
                        state.manager.adopt([config])
                    }
                }
            }
            Text("Adding copies the image, ports, mounts, env vars and limits. The container is not recreated.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
        .padding([.horizontal, .top])
    }

    // MARK: - Containers

    private var emptyState: some View {
                VStack(spacing: 16) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Containers")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Add a container, or press Scan to find ones created outside DevDash")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Add Container") {
                        state.showingAddContainer = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var containersTable: some View {
                Table(containers) {
                    TableColumn("Name") { containerInfo in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor(for: containerInfo.status))
                                .frame(width: 8, height: 8)
                            Text(containerInfo.name)
                                .font(.body)
                        }
                    }
                    .width(min: 120, ideal: 150, max: 200)

                    TableColumn("Image") { containerInfo in
                        Text(containerInfo.image)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .width(min: 150, ideal: 200, max: 300)

                    TableColumn("ID") { containerInfo in
                        if let dockerId = containerInfo.dockerId {
                            InlineCopyableText(dockerId, monospaced: true)
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(min: 120, ideal: 150, max: 200)

                    TableColumn("Status") { containerInfo in
                        Text(containerInfo.status.rawValue.capitalized)
                            .font(.caption)
                            .foregroundColor(statusColor(for: containerInfo.status))
                    }
                    .width(min: 80, ideal: 100, max: 120)

                    TableColumn("Ports") { containerInfo in
                        if !containerInfo.ports.isEmpty {
                            Text(containerInfo.ports.map { $0.dockerFormat }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(min: 100, ideal: 150, max: 250)

                    TableColumn("Actions") { containerInfo in
                        HStack(spacing: 6) {
                            if containerInfo.processingAction != nil {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                if containerInfo.status == .running {
                                    VariantButton(icon: "stop.fill", variant: .danger, tooltip: "Stop") {
                                        if let runtime = state.manager.getRuntime(id: containerInfo.id) {
                                            runtime.stop()
                                        }
                                    }

                                    VariantButton(icon: "arrow.clockwise", variant: .warning, tooltip: "Restart") {
                                        if let runtime = state.manager.getRuntime(id: containerInfo.id) {
                                            runtime.restart()
                                        }
                                    }
                                } else {
                                    VariantButton(icon: "play.fill", variant: .primary, tooltip: "Start") {
                                        if let runtime = state.manager.getRuntime(id: containerInfo.id) {
                                            runtime.start()
                                        }
                                    }
                                }

                                VariantButton(icon: "doc.text", variant: .secondary, tooltip: "View Output") {
                                    containerOutputToView = containerInfo
                                    showingOutput = true
                                }

                                if containerInfo.status == .running, let dockerId = containerInfo.dockerId {
                                    VariantButton(icon: "terminal", variant: .secondary, tooltip: "Logs in Terminal") {
                                        openLogsInTerminal(dockerId: dockerId)
                                    }

                                    VariantButton(icon: "arrow.right.square", variant: .secondary, tooltip: "Exec Shell") {
                                        openExecInTerminal(dockerId: dockerId, name: containerInfo.name)
                                    }
                                }
                            }
                        }
                    }
                    .width(min: 280, ideal: 280, max: 280)

                    TableColumn("") { containerInfo in
                        HStack(spacing: 6) {
                            VariantButton(icon: "pencil", variant: .secondary, tooltip: "Edit") {
                                if let runtime = state.manager.getRuntime(id: containerInfo.id) {
                                    state.containerToEdit = runtime
                                    state.showingEditContainer = true
                                }
                            }

                            VariantButton(icon: "trash", variant: .danger, tooltip: "Delete") {
                                if let runtime = state.manager.getRuntime(id: containerInfo.id) {
                                    state.containerToDelete = runtime
                                    state.showingDeleteContainerConfirmation = true
                                }
                            }
                        }
                    }
                    .width(min: 80, ideal: 80, max: 80)
                }
                .padding()
    }

    private func statusColor(for status: ContainerInfo.ContainerStatus) -> Color {
        switch status {
        case .running: return AppTheme.statusRunning
        case .stopped, .created, .paused: return AppTheme.statusStopped
        case .unknown: return .gray
        }
    }

    private func openLogsInTerminal(dockerId: String) {
        openInTerminal("\(engine.cli) logs -f \(ShellCommand.quote(dockerId))")
    }

    private func openExecInTerminal(dockerId: String, name: String) {
        let id = ShellCommand.quote(dockerId)
        openInTerminal("\(engine.cli) exec -it \(id) /bin/bash || \(engine.cli) exec -it \(id) /bin/sh")
    }

    private func openInTerminal(_ command: String) {
        do {
            try TerminalLauncher.open(command: command)
        } catch {
            state.alertQueue.enqueue(title: "Couldn't Open Terminal", message: error.localizedDescription)
        }
    }
}
