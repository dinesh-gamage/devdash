//
//  VMDetailView.swift
//  DevDash
//

import SwiftUI

struct VMDetailView: View {
    @ObservedObject var state = VMManagerState.shared
    let vm: VMInfo
    @ObservedObject var output: CommandOutputViewModel

    private var action: String? { state.manager.busy[vm.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModuleDetailHeader(
                title: vm.name,
                metadata: metadata,
                actionButtons: {
                    HStack(spacing: 8) {
                        if vm.isRunning {
                            VariantButton("Stop", icon: "stop.fill", variant: .danger, isLoading: action == "Stopping") {
                                Task { await state.manager.stop(vm) }
                            }
                            VariantButton("Shell", icon: "terminal", variant: .secondary) {
                                state.manager.openShell(vm)
                            }
                        } else {
                            VariantButton("Start", icon: "play.fill", variant: .primary, isLoading: action == "Starting") {
                                Task { await state.manager.start(vm) }
                            }
                        }
                        VariantButton(icon: "trash", variant: .danger, tooltip: "Delete VM") {
                            state.vmToDelete = vm
                        }
                    }
                    .disabled(action != nil)
                }
            )

            Divider()

            CommandOutputView(dataSource: output)
        }
    }

    private var metadata: [MetadataRow] {
        let bytes = { (b: Int64?) in b.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } }
        var rows = [
            MetadataRow(icon: "shippingbox", label: "Provider", value: vm.provider.displayName),
            MetadataRow(icon: "circle.fill", label: "Status", value: action ?? vm.status)
        ]
        if let cpus = vm.cpus { rows.append(MetadataRow(icon: "cpu", label: "CPUs", value: "\(cpus)")) }
        if let mem = bytes(vm.memoryBytes) { rows.append(MetadataRow(icon: "memorychip", label: "Memory", value: mem)) }
        if let disk = bytes(vm.diskBytes) { rows.append(MetadataRow(icon: "internaldrive", label: "Disk", value: disk)) }
        if let arch = vm.arch { rows.append(MetadataRow(icon: "cpu.fill", label: "Arch", value: arch)) }
        if let port = vm.sshPort, port > 0 {
            rows.append(MetadataRow(icon: "network", label: "SSH", value: "127.0.0.1:\(port)", copyable: true, monospaced: true))
        }
        if let dir = vm.dir { rows.append(MetadataRow(icon: "folder", label: "Folder", value: dir, copyable: true)) }
        return rows
    }
}
