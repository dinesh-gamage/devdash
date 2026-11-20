//
//  HostedZoneDetailView.swift
//  DevDash
//

import SwiftUI

struct HostedZoneDetailView: View {
    @ObservedObject var state = Route53ManagerState.shared
    let zoneId: UUID

    private enum Tab: String, CaseIterable { case records = "Records", history = "History" }
    @State private var tab: Tab = .records
    @State private var historyRecordId: UUID?   // nil = all records in this zone

    private var manager: Route53Manager { state.manager }

    // Read live data from the manager, not the selection snapshot
    private var zone: HostedZone? {
        manager.zones.first(where: { $0.id == zoneId })
    }

    var body: some View {
        if let zone {
            VStack(alignment: .leading, spacing: 0) {
                ModuleDetailHeader(
                    title: zone.name,
                    metadata: [
                        MetadataRow(icon: "number", label: "Zone ID", value: zone.zoneId, copyable: true, monospaced: true),
                        MetadataRow(icon: "key", label: "Profile", value: zone.awsProfile)
                    ],
                    actionButtons: {
                        HStack(spacing: 12) {
                            VariantButton("Add Record", icon: "plus", variant: .primary) {
                                state.showingAddRecord = true
                            }
                            VariantButton("Edit Zone", icon: "pencil", variant: .secondary) {
                                state.zoneToEdit = zone
                            }
                        }
                    }
                )

                Divider()

                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .padding(12)

                switch tab {
                case .records: recordsTable(zone)
                case .history: historyList(zone)
                }
            }
            .sheet(isPresented: $state.showingAddRecord) {
                DNSRecordFormView(zone: zone, record: nil)
            }
            .sheet(item: $state.recordToEdit) { record in
                DNSRecordFormView(zone: zone, record: record)
            }
            .sheet(item: $state.recordToSetIP) { record in
                SetIPView(record: record) { ip in
                    run { await manager.prepareChange(zone: zone, record: record, newIP: ip, source: "Manual") }
                }
            }
            .alert("Update DNS Record?", isPresented: Binding(
                get: { state.pendingChange != nil },
                set: { if !$0 { state.pendingChange = nil } }
            ), presenting: state.pendingChange) { change in
                Button("Cancel", role: .cancel) { state.pendingChange = nil }
                Button("Update") {
                    state.pendingChange = nil
                    Task { await manager.apply(change) }
                }
            } message: { change in
                Text("\(change.record.name)\n\n\(change.oldIP)  →  \(change.newIP)\n\nSource: \(change.source) • TTL \(change.ttl)s (unchanged)")
            }
            .alert("Remove Record", isPresented: Binding(
                get: { state.recordToDelete != nil },
                set: { if !$0 { state.recordToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { state.recordToDelete = nil }
                Button("Remove", role: .destructive) {
                    if let record = state.recordToDelete {
                        manager.deleteRecord(id: record.id, from: zone.id)
                    }
                    state.recordToDelete = nil
                }
            } message: {
                Text("Remove '\(state.recordToDelete?.name ?? "")' from DevDash? The record in Route 53 is not changed.")
            }
        }
    }

    /// Run a prepare step and, if it returns a change, ask the user to confirm it.
    private func run(_ prepare: @escaping () async -> PendingDNSChange?) {
        Task {
            if let change = await prepare() {
                state.pendingChange = change
            }
        }
    }

    // MARK: - Records

    @ViewBuilder
    private func recordsTable(_ zone: HostedZone) -> some View {
        if zone.records.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No records yet")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Add only the A records you want DevDash to update, e.g. *.v5.\(zone.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(zone.records) {
                TableColumn("Record") { record in
                    InlineCopyableText(record.name, monospaced: true)
                }
                .width(min: 160, ideal: 220)

                TableColumn("Route 53 IP") { record in
                    if manager.busy[record.id] == true {
                        ProgressView().scaleEffect(0.6)
                    } else if let error = record.error {
                        // Show the text itself. Tooltips don't appear reliably inside Table cells.
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .help(error)
                    } else if let ip = record.lastKnownIP {
                        InlineCopyableText(ip, monospaced: true)
                    } else {
                        Text("Not checked").font(.caption).foregroundColor(.secondary)
                    }
                }
                .width(min: 110, ideal: 140)

                TableColumn("Checked") { record in
                    if let date = record.lastChecked {
                        RelativeTimeText(date: date).font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("Never").font(.caption).foregroundColor(.secondary)
                    }
                }
                .width(min: 70, ideal: 90)

                TableColumn("Linked EC2") { record in
                    if record.link == nil {
                        Text("—").foregroundColor(.secondary)
                    } else if let (_, instance) = manager.linkedInstance(for: record) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(instance.name)
                            Text(instance.lastKnownIP ?? "IP not fetched")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Badge("Missing", variant: .warning).help("The linked instance was removed from EC2 Manager")
                    }
                }
                .width(min: 120, ideal: 160)

                TableColumn("Actions") { record in
                    let isBusy = manager.busy[record.id] == true
                    HStack(spacing: 6) {
                        VariantButton(icon: "arrow.clockwise", variant: .secondary, tooltip: "Check Route 53") {
                            Task { await manager.check(zone: zone, record: record) }
                        }
                        VariantButton(icon: "square.and.pencil", variant: .primary, tooltip: "Set IP manually") {
                            state.recordToSetIP = record
                        }
                        if record.link != nil {
                            VariantButton(icon: "cloud.fill", variant: .primary, tooltip: "Update from linked EC2 instance") {
                                run { await manager.prepareChangeFromEC2(zone: zone, record: record) }
                            }
                        }
                        VariantButton(icon: "clock.arrow.circlepath", variant: .secondary, tooltip: "Show history") {
                            historyRecordId = record.id
                            tab = .history
                        }
                        VariantButton(icon: "pencil", variant: .secondary, tooltip: "Edit") {
                            state.recordToEdit = record
                        }
                        VariantButton(icon: "trash", variant: .danger, tooltip: "Remove from DevDash") {
                            state.recordToDelete = record
                        }
                    }
                    .disabled(isBusy)
                }
                .width(min: 220, ideal: 240)
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private func historyList(_ zone: HostedZone) -> some View {
        let entries = manager.changeLog.filter {
            $0.zoneId == zone.id && (historyRecordId == nil || $0.recordId == historyRecordId)
        }

        VStack(alignment: .leading, spacing: 0) {
            Picker("Record", selection: $historyRecordId) {
                Text("All records").tag(UUID?.none)
                ForEach(zone.records) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if entries.isEmpty {
                Text("No changes yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(entries) {
                    TableColumn("When") { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.date, format: .dateTime.year().month().day().hour().minute().second())
                            RelativeTimeText(date: e.date).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .width(min: 150, ideal: 170)

                    TableColumn("Record") { e in
                        Text(e.recordName).font(.body.monospaced())
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Change") { e in
                        Text("\(e.oldIP ?? "—")  →  \(e.newIP)").font(.body.monospaced())
                    }
                    .width(min: 200, ideal: 240)

                    TableColumn("Source") { e in
                        Text(e.source).font(.caption)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("Result") { e in
                        if e.success {
                            Badge("Done", variant: .primary)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Badge("Failed", variant: .danger)
                                if let error = e.error {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .lineLimit(3)
                                        .textSelection(.enabled)
                                        .help(error)
                                }
                            }
                        }
                    }
                    .width(min: 120, ideal: 200)
                }
            }
        }
    }
}
