//
//  ServiceDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct ServiceDetailView: View {
    @ObservedObject var service: ServiceRuntime
    @State private var input = ""

    /// Script services start in the background on purpose, so "outside DevDash" doesn't apply
    private var showsExternal: Bool { service.isExternallyManaged && service.config.script == nil }

    var body: some View {
        ServiceOutputPanel(
            title: service.config.name,
            metadata: buildMetadata(),
            dataSource: service,
            actionButtons: {
                HStack {
                    if service.isRunning {
                        if showsExternal {
                            Badge("Running outside DevDash", icon: "exclamationmark.triangle", variant: .warning)
                        }

                        VariantButton("Stop", variant: .danger, isLoading: service.processingAction == .stopping) {
                            service.stop()
                        }
                        .disabled(service.processingAction != nil)

                        VariantButton("Restart", variant: .warning, isLoading: service.processingAction == .restarting) {
                            service.restart()
                        }
                        .disabled(service.processingAction != nil)

                        if showsExternal {
                            VariantButton("Kill & Start", variant: .danger, isLoading: service.processingAction == .killingAndRestarting) {
                                service.killAndRestart()
                            }
                            .disabled(service.processingAction != nil)
                        }
                    } else if service.hasPortConflict {
                        Badge("Port \(service.config.port ?? 0) in use (PID: \(service.conflictingPID ?? 0))", icon: "exclamationmark.triangle", variant: .warning)

                        VariantButton("Kill & Restart", variant: .danger, isLoading: service.processingAction == .killingAndRestarting) {
                            service.killAndRestart()
                        }
                        .disabled(service.processingAction != nil)
                    } else {
                        VariantButton("Start", icon: "play.fill", variant: .primary, isLoading: service.processingAction == .starting) {
                            service.start()
                        }
                        .disabled(service.processingAction != nil)
                    }

                    if service.acceptsInput {
                        TextField("Send input", text: $input)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                            .onSubmit {
                                service.sendInput(input)
                                input = ""
                            }
                    }

                    VariantButton(icon: "arrow.clockwise", variant: .secondary, tooltip: "Check service status") {
                        Task { await service.checkStatus() }
                    }
                }
            },
            statusContent: {
                HStack(spacing: 12) {
                    // Status indicator
                    Circle()
                        .fill(service.isRunning ? AppTheme.statusRunning : AppTheme.statusStopped)
                        .frame(width: 12, height: 12)

                    Text(service.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        )
        .sheet(isPresented: Binding(
            get: { service.pendingPrompt != nil },
            set: { if !$0 { service.pendingPrompt = nil } }
        )) {
            ServiceInputPrompt(service: service)
        }
        .task {
            await service.checkStatus()
        }
    }

    private func buildMetadata() -> [MetadataRow] {
        var rows: [MetadataRow] = []

        // Command (copyable)
        rows.append(MetadataRow(
            icon: "terminal",
            label: "Command",
            value: service.config.command,
            copyable: true
        ))

        // Directory (copyable)
        rows.append(MetadataRow(
            icon: "folder",
            label: "Directory",
            value: service.config.workingDirectory,
            copyable: true
        ))

        // Port (optional)
        if let port = service.config.port {
            rows.append(MetadataRow(
                icon: "network",
                label: "Port",
                value: "\(port)"
            ))
        }

        // Environment (optional)
        if !service.config.environment.isEmpty {
            rows.append(MetadataRow(
                icon: "gearshape",
                label: "Environment",
                value: service.config.environment.keys.joined(separator: ", ")
            ))
        }

        // Prerequisites (optional)
        if let prereqs = service.config.prerequisites, !prereqs.isEmpty {
            rows.append(MetadataRow(
                icon: "list.bullet.clipboard",
                label: "Prerequisites",
                value: "\(prereqs.count) command(s)"
            ))
        }

        return rows
    }
}

/// Popup for a service that is waiting for input
struct ServiceInputPrompt: View {
    @Environment(\.dismiss) var dismiss
    let service: ServiceRuntime
    @State private var answer = ""

    private var prompt: String { service.pendingPrompt ?? "" }
    private var isSecret: Bool {
        let p = prompt.lowercased()
        return ["password", "passphrase", "pin", "secret", "token"].contains { p.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(service.config.name) is asking for input").font(.headline)
            Text(prompt).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Group {
                if isSecret {
                    SecureField("Answer", text: $answer)
                } else {
                    TextField("Answer", text: $answer)
                }
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit(send)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send", action: send).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func send() {
        service.sendInput(answer)
        dismiss()
    }
}
