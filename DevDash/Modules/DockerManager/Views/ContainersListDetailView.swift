//
//  ContainersListDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

struct ContainersListDetailView: View {
    @ObservedObject var state = DockerManagerState.shared

    @State private var containerOutputToView: ContainerInfo? = nil
    @State private var showingOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ModuleDetailHeader(
                title: "Containers",
                actionButtons: {
                    HStack(spacing: 8) {
                        VariantButton("Add Container", icon: "plus", variant: .primary) {
                            state.showingAddContainer = true
                        }

                        VariantButton(icon: "arrow.clockwise", variant: .secondary, tooltip: "Refresh") {
                            Task {
                                await state.manager.refreshContainersList()
                            }
                        }
                    }
                }
            )

            Divider()

            // Conditional: Show output panel OR container table
            if showingOutput,
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
            } else if state.manager.containersList.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Containers")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Add a container to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Add Container") {
                        state.showingAddContainer = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(state.manager.containersList) {
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

                    TableColumn("Docker ID") { containerInfo in
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
        }
        .task {
            await state.manager.refreshContainersList()
        }
    }

    private func statusColor(for status: ContainerInfo.ContainerStatus) -> Color {
        switch status {
        case .running: return AppTheme.statusRunning
        case .stopped, .created, .paused: return AppTheme.statusStopped
        case .unknown: return .gray
        }
    }

    private func openLogsInTerminal(dockerId: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "docker logs -f \(dockerId)"
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if let error = error {
            print("AppleScript error: \(error)")
        }
    }

    private func openExecInTerminal(dockerId: String, name: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "docker exec -it \(dockerId) /bin/sh || docker exec -it \(dockerId) /bin/bash"
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        if let error = error {
            print("AppleScript error: \(error)")
        }
    }
}
