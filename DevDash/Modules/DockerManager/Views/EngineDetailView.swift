//
//  EngineDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

/// Start / stop / restart an engine host (Colima or Apple's container system).
/// For Colima it also creates, edits and deletes the instance.
struct EngineDetailView: View {
    @ObservedObject var host: EngineRuntime
    @State private var showingConfig = false
    @State private var showingDelete = false

    /// Colima with no instance yet
    private var needsSetup: Bool { host.engine == .docker && host.colima == nil }

    var body: some View {
        ServiceOutputPanel(
            title: host.name,
            metadata: metadata,
            dataSource: host,
            actionButtons: {
                HStack(spacing: 8) {
                    if needsSetup {
                        VariantButton("Create Instance", icon: "plus", variant: .primary, isLoading: host.processingAction == .starting) {
                            showingConfig = true
                        }
                    } else if host.isRunning {
                        VariantButton("Stop", variant: .danger, isLoading: host.processingAction == .stopping) {
                            host.stop()
                        }
                        VariantButton("Restart", variant: .warning, isLoading: host.processingAction == .restarting) {
                            host.restart()
                        }
                    } else {
                        VariantButton("Start", icon: "play.fill", variant: .primary, isLoading: host.processingAction == .starting) {
                            host.start()
                        }
                    }

                    if host.engine == .docker && !needsSetup {
                        VariantButton(icon: "pencil", variant: .secondary, tooltip: "Edit CPUs, memory and disk") {
                            showingConfig = true
                        }
                        VariantButton(icon: "trash", variant: .danger, tooltip: "Delete Colima instance") {
                            showingDelete = true
                        }
                    }

                    VariantButton(icon: "arrow.clockwise", variant: .secondary, tooltip: "Check status") {
                        Task { await host.checkStatus() }
                    }
                }
                .disabled(host.processingAction != nil)
            },
            statusContent: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(host.isRunning ? AppTheme.statusRunning : AppTheme.statusStopped)
                        .frame(width: 12, height: 12)

                    Text(host.isRunning ? "Running" : needsSetup ? "Not set up" : "Stopped")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        )
        .sheet(isPresented: $showingConfig) {
            ColimaConfigView(host: host)
        }
        .alert("Delete Colima Instance", isPresented: $showingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete, Keep Data") { host.deleteColima(withData: false) }
            Button("Delete Everything", role: .destructive) { host.deleteColima(withData: true) }
        } message: {
            Text("'Delete, Keep Data' keeps images and volumes for the next instance. 'Delete Everything' removes them too. That cannot be undone.")
        }
        .task {
            await host.checkStatus()
        }
    }

    private var metadata: [MetadataRow] {
        var rows = [MetadataRow(icon: "info.circle", label: host.engine.hostDescription)]
        if let c = host.colima {
            if let cpus = c.cpus { rows.append(MetadataRow(icon: "cpu", label: "CPUs", value: "\(cpus)")) }
            if let mem = c.memoryGiB { rows.append(MetadataRow(icon: "memorychip", label: "Memory", value: "\(mem) GiB")) }
            if let disk = c.diskGiB { rows.append(MetadataRow(icon: "internaldrive", label: "Disk", value: "\(disk) GiB")) }
            if let runtime = c.runtime { rows.append(MetadataRow(icon: "shippingbox", label: "Runtime", value: runtime)) }
        }
        return rows
    }
}

/// Create the Colima instance, or change its specs
struct ColimaConfigView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var host: EngineRuntime

    @State private var cpus = 2
    @State private var memoryGiB = 4
    @State private var diskGiB = 100

    private var creating: Bool { host.colima == nil }
    private let maxCPUs = ProcessInfo.processInfo.processorCount
    private let maxMemoryGiB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    /// Colima can grow a disk but not shrink it
    private var minDiskGiB: Int { host.colima?.diskGiB ?? 10 }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("CPUs: \(cpus)", value: $cpus, in: 1...maxCPUs)
                Stepper("Memory: \(memoryGiB) GiB", value: $memoryGiB, in: 1...maxMemoryGiB)
                Stepper("Disk: \(diskGiB) GiB", value: $diskGiB, in: minDiskGiB...2000, step: 10)
                Text(creating
                     ? "Creates the default Colima instance with the Docker runtime and starts it."
                     : "Colima restarts to apply the change. Running containers stop. The disk can only grow.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .formStyle(.grouped)
            .navigationTitle(creating ? "Create Colima Instance" : "Edit Colima Instance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(creating ? "Create" : "Apply") {
                        host.configureColima(cpus: cpus, memoryGiB: memoryGiB, diskGiB: diskGiB)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 280)
        .onAppear {
            guard let c = host.colima else { return }
            cpus = c.cpus ?? cpus
            memoryGiB = c.memoryGiB ?? memoryGiB
            diskGiB = max(c.diskGiB ?? diskGiB, minDiskGiB)
        }
    }
}
