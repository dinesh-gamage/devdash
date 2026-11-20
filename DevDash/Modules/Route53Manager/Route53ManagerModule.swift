//
//  Route53ManagerModule.swift
//  DevDash
//

import SwiftUI
import Combine

struct Route53ManagerModule: DevDashModule {
    let id = "route53-manager"
    let name = "Route 53 Records"
    let icon = "network"
    let description = "Update DNS A records when EC2 IPs change"
    let accentColor = Color.teal

    func makeSidebarView() -> AnyView {
        AnyView(Route53ManagerSidebarView())
    }

    func makeDetailView() -> AnyView {
        AnyView(Route53ManagerDetailView())
    }

    // MARK: - Backup Support

    var backupFileName: String {
        "route53.json"
    }

    func exportForBackup() async throws -> Data {
        try Route53ManagerState.shared.manager.exportBackupData()
    }
}

// MARK: - Shared State

@MainActor
class Route53ManagerState: ObservableObject {
    static let shared = Route53ManagerState()

    let alertQueue = AlertQueue()
    let toastQueue = ToastQueue()
    @Published var manager: Route53Manager
    @Published var selectedZone: HostedZone?

    // Zone sheets / confirmations
    @Published var showingAddZone = false
    @Published var zoneToEdit: HostedZone?
    @Published var zoneToDelete: HostedZone?

    // Record sheets / confirmations
    @Published var showingAddRecord = false
    @Published var recordToEdit: DNSRecord?
    @Published var recordToDelete: DNSRecord?
    @Published var recordToSetIP: DNSRecord?

    // Change waiting for confirmation (old → new)
    @Published var pendingChange: PendingDNSChange?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.manager = Route53Manager(alertQueue: alertQueue, toastQueue: toastQueue)

        // Forward manager changes to state so views update
        manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }
}

// MARK: - Sidebar View

struct Route53ManagerSidebarView: View {
    @ObservedObject var state = Route53ManagerState.shared

    var body: some View {
        ModuleSidebarList(
            toolbarButtons: [
                ToolbarButtonConfig(icon: "plus.circle", help: "Add Hosted Zone") {
                    state.showingAddZone = true
                }
            ],
            items: state.manager.zones,
            emptyState: EmptyStateConfig(
                icon: "network",
                title: "No Hosted Zones",
                subtitle: "Add a zone, then add only the records you want to manage",
                buttonText: "Add Zone",
                buttonIcon: "plus",
                buttonAction: { state.showingAddZone = true }
            ),
            selectedItem: $state.selectedZone
        ) { zone, isSelected in
            ModuleSidebarListItem(
                icon: .none,
                title: zone.name,
                subtitle: "\(zone.awsProfile) • \(zone.records.count) records",
                badge: zone.records.contains { $0.error != nil } ? Badge("!", variant: .danger) : nil,
                actions: [
                    ListItemAction(icon: "pencil", variant: .primary, tooltip: "Edit") {
                        state.zoneToEdit = zone
                    },
                    ListItemAction(icon: "trash", variant: .danger, tooltip: "Delete") {
                        state.zoneToDelete = zone
                    }
                ],
                isSelected: isSelected,
                onTap: { state.selectedZone = zone }
            )
        }
        .sheet(isPresented: $state.showingAddZone) {
            HostedZoneFormView(zone: nil)
        }
        .sheet(item: $state.zoneToEdit) { zone in
            HostedZoneFormView(zone: zone)
        }
        .alertQueue(state.alertQueue)
        .alert("Delete Zone", isPresented: Binding(
            get: { state.zoneToDelete != nil },
            set: { if !$0 { state.zoneToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { state.zoneToDelete = nil }
            Button("Delete", role: .destructive) {
                if let zone = state.zoneToDelete {
                    if state.selectedZone?.id == zone.id { state.selectedZone = nil }
                    state.manager.deleteZone(id: zone.id)
                    state.toastQueue.enqueue(message: "'\(zone.name)' removed from DevDash")
                }
                state.zoneToDelete = nil
            }
        } message: {
            if let zone = state.zoneToDelete {
                Text("Remove '\(zone.name)' and its \(zone.records.count) record(s) from DevDash? Nothing changes in Route 53.")
            }
        }
        .onAppear {
            AppTheme.AccentColor.shared.set(.teal)
        }
    }
}

// MARK: - Detail View

struct Route53ManagerDetailView: View {
    @ObservedObject var state = Route53ManagerState.shared

    var body: some View {
        if let zone = state.selectedZone {
            HostedZoneDetailView(zoneId: zone.id)
                .id(zone.id)  // Reset tab/filter when switching zones
        } else {
            VStack(spacing: 16) {
                Image(systemName: "network")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)

                Text("Select a Hosted Zone")
                    .font(.title2)
                    .foregroundColor(.secondary)

                Text("Choose a zone from the sidebar to manage its records")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
