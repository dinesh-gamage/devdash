//
//  VMManagerModule.swift
//  DevDash
//

import SwiftUI
import Combine

struct VMManagerModule: DevDashModule {
    let id = "vm-manager"
    let name = "Virtual Machines"
    let icon = "desktopcomputer"
    let description = "Lima VMs and Apple container machines"
    let accentColor = Color.indigo

    func makeSidebarView() -> AnyView {
        AnyView(VMManagerSidebarView())
    }

    func makeDetailView() -> AnyView {
        AnyView(VMManagerDetailView())
    }

    // MARK: - Backup Support

    var backupFileName: String {
        "vms.json"
    }

    func exportForBackup() async throws -> Data {
        try await VMManagerState.shared.manager.exportBackupData()
    }
}

// MARK: - Shared State

@MainActor
class VMManagerState: ObservableObject {
    static let shared = VMManagerState()

    let alertQueue = AlertQueue()
    let toastQueue = ToastQueue()
    @Published var manager: VMManager
    @Published var selectedVM: VMInfo?
    @Published var vmToDelete: VMInfo?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.manager = VMManager(alertQueue: alertQueue, toastQueue: toastQueue)

        // Forward manager changes to state so views update
        manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }
}

// MARK: - Sidebar View

struct VMManagerSidebarView: View {
    @ObservedObject var state = VMManagerState.shared

    var body: some View {
        ModuleSidebarList(
            toolbarButtons: [
                ToolbarButtonConfig(icon: "arrow.clockwise", help: "Refresh") {
                    Task { await state.manager.refresh() }
                }
            ],
            items: state.manager.vms,
            emptyState: EmptyStateConfig(
                icon: "desktopcomputer",
                title: state.manager.isLoading ? "Loading..." : "No VMs Found",
                subtitle: "Create one with limactl or container machine create"
            ),
            selectedItem: $state.selectedVM
        ) { vm, isSelected in
            let action = state.manager.busy[vm.id]
            return ModuleSidebarListItem(
                icon: .image(systemName: vm.provider.icon, color: vm.isRunning ? AppTheme.statusRunning : AppTheme.statusStopped),
                title: vm.name,
                subtitle: "\(vm.provider.displayName) • \(action ?? vm.status)",
                isSelected: isSelected,
                onTap: { state.selectedVM = vm }
            )
        }
        .alertQueue(state.alertQueue)
        .alert("Delete VM", isPresented: Binding(
            get: { state.vmToDelete != nil },
            set: { if !$0 { state.vmToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { state.vmToDelete = nil }
            Button("Delete", role: .destructive) {
                if let vm = state.vmToDelete {
                    if state.selectedVM?.id == vm.id { state.selectedVM = nil }
                    Task { await state.manager.delete(vm) }
                }
                state.vmToDelete = nil
            }
        } message: {
            if let vm = state.vmToDelete {
                Text("Delete '\(vm.name)' and its disk? This cannot be undone.")
            }
        }
        .task {
            await state.manager.refresh()
        }
        .onAppear {
            AppTheme.AccentColor.shared.set(.indigo)
        }
    }
}

// MARK: - Detail View

struct VMManagerDetailView: View {
    @ObservedObject var state = VMManagerState.shared

    var body: some View {
        // Read live data from the manager, not the selection snapshot
        if let id = state.selectedVM?.id, let vm = state.manager.vms.first(where: { $0.id == id }) {
            VMDetailView(vm: vm, output: state.manager.output(for: vm))
                .id(vm.id)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)

                Text("Select a VM")
                    .font(.title2)
                    .foregroundColor(.secondary)

                Text("Choose a VM from the sidebar to start, stop or open a shell")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
