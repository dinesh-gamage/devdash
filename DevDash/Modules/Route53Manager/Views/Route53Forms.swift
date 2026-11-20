//
//  Route53Forms.swift
//  DevDash
//
//  Add/edit forms for hosted zones and records, plus the manual "Set IP" sheet.
//

import SwiftUI

// MARK: - Hosted Zone Form

struct HostedZoneFormView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var state = Route53ManagerState.shared
    @ObservedObject var awsVaultState = AWSVaultManagerState.shared

    let zone: HostedZone?   // nil = add

    @State private var name = ""
    @State private var zoneId = ""
    @State private var awsProfile = ""

    private var normalizedZoneId: String { DNSName.normalizeZoneId(zoneId) }
    private var zoneIdValid: Bool { DNSName.isValidZoneId(normalizedZoneId) }
    private var canSave: Bool { !DNSName.normalize(name).isEmpty && zoneIdValid && !awsProfile.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hosted Zone") {
                    TextField("Domain (e.g., lucyday.io)", text: $name)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Hosted Zone ID (e.g., Z0123456789ABC)", text: $zoneId)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                        if !zoneId.isEmpty && !zoneIdValid {
                            Text("Zone IDs start with Z. Copy it from the Route 53 console.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Picker("AWS Profile", selection: $awsProfile) {
                            Text("Select a profile").tag("")
                            ForEach(awsVaultState.manager.getProfileNames(), id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)

                        if awsVaultState.manager.getProfileNames().isEmpty {
                            Text("No profiles found. Add profiles in AWS Vault Manager.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Section {
                    Text("DevDash only reads and updates the records you add. Other records in this zone are never touched.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(zone == nil ? "Add Hosted Zone" : "Edit Hosted Zone")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(zone == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 320)
        .onAppear {
            if let zone {
                name = zone.name
                zoneId = zone.zoneId
                awsProfile = zone.awsProfile
            }
        }
    }

    private func save() {
        let cleanName = DNSName.normalize(name)
        if var existing = zone {
            existing.name = cleanName
            existing.zoneId = normalizedZoneId
            existing.awsProfile = awsProfile
            state.manager.updateZone(existing)
            if state.selectedZone?.id == existing.id { state.selectedZone = existing }
        } else {
            let newZone = HostedZone(name: cleanName, zoneId: normalizedZoneId, awsProfile: awsProfile)
            state.manager.addZone(newZone)
            state.selectedZone = newZone
        }
        dismiss()
    }
}

// MARK: - DNS Record Form

struct DNSRecordFormView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var state = Route53ManagerState.shared
    @ObservedObject var ec2State = EC2ManagerState.shared

    let zone: HostedZone
    let record: DNSRecord?   // nil = add

    @State private var name = ""
    @State private var link: InstanceLink?

    private var cleanName: String { DNSName.normalize(name) }
    private var belongsToZone: Bool { DNSName.record(cleanName, belongsTo: zone.name) }
    private var isDuplicate: Bool {
        zone.records.contains { $0.id != record?.id && DNSName.normalize($0.name) == cleanName }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("A Record") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Record name (e.g., *.v5.\(zone.name))", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                        if !cleanName.isEmpty && !belongsToZone {
                            Text("The name must end with .\(zone.name)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else if isDuplicate {
                            Text("This record is already in the list.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Section("Link to EC2 Instance (optional)") {
                    Picker("Instance", selection: $link) {
                        Text("None (set IP manually)").tag(InstanceLink?.none)
                        ForEach(ec2State.manager.groups) { group in
                            Section(group.name) {
                                ForEach(group.instances) { instance in
                                    Text("\(instance.name) (\(instance.instanceId))")
                                        .tag(InstanceLink?.some(InstanceLink(groupId: group.id, instanceId: instance.id)))
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)

                    Text("When linked, one click fetches the instance's current public IP and updates this record.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(record == nil ? "Add Record" : "Edit Record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(record == nil ? "Add" : "Save") { save() }
                        .disabled(!belongsToZone || isDuplicate)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 320)
        .onAppear {
            if let record {
                name = record.name
                link = record.link
            }
        }
    }

    private func save() {
        if var existing = record {
            if DNSName.normalize(existing.name) != cleanName {
                // Different record now. The cached value belongs to the old name.
                existing.lastKnownIP = nil
                existing.lastChecked = nil
                existing.error = nil
            }
            existing.name = cleanName
            existing.link = link
            state.manager.updateRecord(existing, in: zone.id)
        } else {
            state.manager.addRecord(DNSRecord(name: cleanName, link: link), to: zone.id)
        }
        dismiss()
    }
}

// MARK: - Set IP Sheet

struct SetIPView: View {
    @Environment(\.dismiss) var dismiss
    let record: DNSRecord
    let onSubmit: (String) -> Void

    @State private var ip = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(record.name) {
                    TextField("New IPv4 address", text: $ip)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .onSubmit(submit)

                    if let current = record.lastKnownIP {
                        Text("Last seen in Route 53: \(current)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("DevDash reads the live record first and asks you to confirm before changing it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Set IP")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: submit)
                        .disabled(ip.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 220)
    }

    private func submit() {
        let value = ip
        dismiss()
        onSubmit(value)
    }
}
