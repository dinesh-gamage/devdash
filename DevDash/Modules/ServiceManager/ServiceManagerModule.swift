//
//  ServiceManagerModule.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI
import Combine

struct ServiceManagerModule: DevDashModule {
    let id = "service-manager"
    let name = "Service Manager"
    let icon = "gearshape.2.fill"
    let description = "Manage local development services"
    let accentColor = Color.blue

    func makeSidebarView() -> AnyView {
        AnyView(ServiceManagerSidebarView())
    }

    func makeDetailView() -> AnyView {
        AnyView(ServiceManagerDetailView())
    }

    // MARK: - Backup Support

    var backupFileName: String {
        "services.json"
    }

    func exportForBackup() async throws -> Data {
        let manager = ServiceManagerState.shared.manager
        let configs = manager.services.map { $0.config }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(configs)
    }
}

// MARK: - Shared State

@MainActor
class ServiceManagerState: ObservableObject {
    static let shared = ServiceManagerState()

    let alertQueue = AlertQueue()
    let toastQueue = ToastQueue()
    @Published var manager: ServiceManager
    @Published var selectedService: ServiceRuntime?
    @Published var showingAddService = false
    @Published var showingEditService = false
    @Published var showingJSONEditor = false
    @Published var serviceToEdit: ServiceRuntime?
    @Published var serviceToDelete: ServiceRuntime?
    @Published var showingDeleteConfirmation = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.manager = ServiceManager(alertQueue: alertQueue, toastQueue: toastQueue)

        // Forward manager changes to state so sidebar updates
        manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }
}

// MARK: - Sidebar View

struct ServiceManagerSidebarView: View {
    @ObservedObject var state = ServiceManagerState.shared

    var body: some View {
        ModuleSidebarList(
            toolbarButtons: [
                ToolbarButtonConfig(icon: "plus.circle", help: "Add Service") {
                    state.showingAddService = true
                },
                ToolbarButtonConfig(icon: "square.and.arrow.down", help: "Import Services") {
                    state.manager.importServices()
                },
                ToolbarButtonConfig(icon: "square.and.arrow.up", help: "Export Services") {
                    state.manager.exportServices()
                },
                ToolbarButtonConfig(icon: "curlybraces", help: "Edit JSON") {
                    state.showingJSONEditor = true
                },
                ToolbarButtonConfig(icon: "arrow.clockwise", help: "Refresh All") {
                    state.manager.checkAllServices()
                }
            ],
            items: state.manager.servicesList,
            emptyState: EmptyStateConfig(
                icon: "gearshape.2",
                title: "No Services",
                subtitle: "Add a service to get started",
                buttonText: "Add Service",
                buttonIcon: "plus",
                buttonAction: { state.showingAddService = true }
            ),
            selectedItem: Binding(
                get: {
                    if let selected = state.selectedService {
                        return state.manager.servicesList.first(where: { $0.id == selected.id })
                    }
                    return nil
                },
                set: { newValue in
                    if let serviceInfo = newValue {
                        state.selectedService = state.manager.getRuntime(id: serviceInfo.id)
                    } else {
                        state.selectedService = nil
                    }
                }
            ),
            searchEnabled: true,
            searchPlaceholder: "Search services...",
            searchFilter: { serviceInfo, searchText in
                serviceInfo.name.localizedCaseInsensitiveContains(searchText) ||
                serviceInfo.command.localizedCaseInsensitiveContains(searchText) ||
                serviceInfo.workingDirectory.localizedCaseInsensitiveContains(searchText)
            }
        ) { serviceInfo, isSelected in
            // Build actions array based on service state
            var actions: [ListItemAction] = []

            if serviceInfo.isRunning {
                actions.append(
                    ListItemAction(icon: "stop.fill", variant: .danger, tooltip: "Stop") {
                        state.manager.getRuntime(id: serviceInfo.id)?.stop()
                    }
                )
                actions.append(
                    ListItemAction(icon: "arrow.clockwise", variant: .primary, tooltip: "Restart") {
                        state.manager.getRuntime(id: serviceInfo.id)?.restart()
                    }
                )
            } else {
                actions.append(
                    ListItemAction(icon: "play.fill", variant: .primary, tooltip: "Start") {
                        state.manager.getRuntime(id: serviceInfo.id)?.start()
                    }
                )
            }

            // Add divider and edit/delete
            actions.append(
                ListItemAction(icon: "pencil", variant: .primary, tooltip: "Edit") {
                    if let runtime = state.manager.getRuntime(id: serviceInfo.id) {
                        state.serviceToEdit = runtime
                        state.showingEditService = true
                    }
                }
            )
            actions.append(
                ListItemAction(icon: "trash", variant: .danger, tooltip: "Delete") {
                    if let runtime = state.manager.getRuntime(id: serviceInfo.id) {
                        state.serviceToDelete = runtime
                        state.showingDeleteConfirmation = true
                    }
                }
            )

            return ModuleSidebarListItem(
                icon: .status(color: serviceInfo.isRunning ? AppTheme.statusRunning : AppTheme.statusStopped),
                title: serviceInfo.name,
                subtitle: nil,
                badge: nil,
                actions: actions,
                isSelected: isSelected,
                onTap: {
                    state.selectedService = state.manager.getRuntime(id: serviceInfo.id)
                }
            )
        }
        .sheet(isPresented: $state.showingAddService) {
            AddServiceView(manager: state.manager)
        }
        .sheet(isPresented: $state.showingEditService) {
            if let service = state.serviceToEdit {
                EditServiceView(manager: state.manager, service: service)
            }
        }
        .sheet(isPresented: $state.showingJSONEditor) {
            JSONEditorView(manager: state.manager)
        }
        .alertQueue(state.alertQueue)
        .alert("Delete Service", isPresented: $state.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                state.serviceToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let service = state.serviceToDelete,
                   let index = state.manager.servicesList.firstIndex(where: { $0.id == service.id }) {
                    let serviceName = service.config.name
                    // Clear selection if deleting selected service
                    if state.selectedService?.id == service.id {
                        state.selectedService = nil
                    }
                    state.manager.deleteService(at: IndexSet(integer: index))
                    state.toastQueue.enqueue(message: "'\(serviceName)' deleted")
                    state.serviceToDelete = nil
                }
            }
        } message: {
            if let service = state.serviceToDelete {
                Text("Are you sure you want to delete '\(service.config.name)'? This action cannot be undone.")
            }
        }
        .onAppear {
            AppTheme.AccentColor.shared.set(.blue)
            state.manager.checkAllServices()
        }
    }
}

// MARK: - Detail View

struct ServiceManagerDetailView: View {
    @ObservedObject var state = ServiceManagerState.shared

    var body: some View {
        if let service = state.selectedService {
            ServiceDetailView(service: service)
                .id(ObjectIdentifier(service))
        } else {
            VStack(spacing: 16) {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)

                Text("Select a Service")
                    .font(.title2)
                    .foregroundColor(.secondary)

                Text("Choose a service from the sidebar to view details")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
