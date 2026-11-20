//
//  Route53Manager.swift
//  DevDash
//
//  Keeps selected Route 53 A records pointed at the right IP.
//  Only ever reads or UPSERTs the records the user configured. Never touches other records.
//

import Foundation
import Combine
import Network

@MainActor
class Route53Manager: ObservableObject {
    @Published var zones: [HostedZone] = []
    @Published var changeLog: [IPChangeLogEntry] = []   // Newest first
    @Published var busy: [UUID: Bool] = [:]             // Keyed by record id

    private weak var alertQueue: AlertQueue?
    private weak var toastQueue: ToastQueue?

    private let zonesKey = "route53Zones"
    private let logKey = "route53ChangeLog"
    // ponytail: log capped at 500 entries in UserDefaults. Move to a file if more history is needed.
    private let maxLogEntries = 500

    init(alertQueue: AlertQueue? = nil, toastQueue: ToastQueue? = nil) {
        self.alertQueue = alertQueue
        self.toastQueue = toastQueue
        zones = StorageManager.shared.load(forKey: zonesKey) ?? []
        changeLog = StorageManager.shared.load(forKey: logKey) ?? []
    }

    private func saveZones() { StorageManager.shared.save(zones, forKey: zonesKey) }
    private func saveLog() { StorageManager.shared.save(changeLog, forKey: logKey) }

    // MARK: - Zone CRUD

    func addZone(_ zone: HostedZone) {
        zones.append(zone)
        saveZones()
    }

    func updateZone(_ zone: HostedZone) {
        guard let i = zones.firstIndex(where: { $0.id == zone.id }) else { return }
        zones[i] = zone
        saveZones()
    }

    func deleteZone(id: UUID) {
        zones.removeAll { $0.id == id }
        saveZones()
    }

    // MARK: - Record CRUD

    func addRecord(_ record: DNSRecord, to zoneId: UUID) {
        guard let i = zones.firstIndex(where: { $0.id == zoneId }) else { return }
        zones[i].records.append(record)
        saveZones()
    }

    func updateRecord(_ record: DNSRecord, in zoneId: UUID) {
        mutateRecord(zoneId, record.id) { $0 = record }
    }

    func deleteRecord(id: UUID, from zoneId: UUID) {
        guard let i = zones.firstIndex(where: { $0.id == zoneId }) else { return }
        zones[i].records.removeAll { $0.id == id }
        saveZones()
    }

    private func mutateRecord(_ zoneId: UUID, _ recordId: UUID, _ change: (inout DNSRecord) -> Void) {
        guard let z = zones.firstIndex(where: { $0.id == zoneId }),
              let r = zones[z].records.firstIndex(where: { $0.id == recordId }) else { return }
        change(&zones[z].records[r])
        saveZones()
    }

    // MARK: - EC2 Link

    /// Resolve a record's linked EC2 instance from the EC2 Manager module.
    func linkedInstance(for record: DNSRecord) -> (group: InstanceGroup, instance: EC2Instance)? {
        guard let link = record.link,
              let group = EC2ManagerState.shared.manager.groups.first(where: { $0.id == link.groupId }),
              let instance = group.instances.first(where: { $0.id == link.instanceId }) else { return nil }
        return (group, instance)
    }

    // MARK: - Route 53 Read

    private struct LiveRecord {
        let ips: [String]
        let ttl: Int
    }

    /// Read the live A record. Updates the cached IP / error on the record.
    @discardableResult
    func check(zone: HostedZone, record: DNSRecord) async -> Bool {
        busy[record.id] = true
        defer { busy[record.id] = false }
        return await readLive(zone: zone, record: record) != nil
    }

    /// AWS environment for a profile, or the aws-vault error.
    /// ProcessEnvironment silently falls back to no credentials, which hides the real reason ("NoCredentials").
    private func awsEnvironment(profile: String) async -> (env: [String: String]?, error: String?) {
        // Route 53 is global, but aws-vault's STS call needs a region. us-east-1 is Route 53's home region.
        let region = "us-east-1"
        guard await AWSVaultServerManager.shared.getSession(for: profile, region: region) != nil else {
            let reason = AWSVaultServerManager.shared.sessionErrors[profile] ?? "Unknown error"
            return (nil, "aws-vault could not get a session for '\(profile)': \(reason)")
        }
        return (await ProcessEnvironment.shared.getEnvironment(withAWSProfile: profile, region: region), nil)
    }

    private func readLive(zone: HostedZone, record: DNSRecord) async -> LiveRecord? {
        let (envOrNil, envError) = await awsEnvironment(profile: zone.awsProfile)
        guard let env = envOrNil else {
            mutateRecord(zone.id, record.id) {
                $0.lastChecked = Date()
                $0.error = envError
            }
            return nil
        }
        let args = ["route53", "list-resource-record-sets",
                    "--hosted-zone-id", zone.zoneId,
                    "--start-record-name", record.name,
                    "--start-record-type", "A",
                    "--max-items", "1",
                    "--output", "json"]
        let result = await ShellCommand.run("aws", args, env: env)

        let live: LiveRecord?
        let error: String?
        if result.exitCode != 0 {
            (live, error) = (nil, result.stderr.isEmpty ? "aws exited with \(result.exitCode)" : result.stderr)
        } else {
            (live, error) = parse(result.stdout, expectedName: record.name)
        }

        mutateRecord(zone.id, record.id) {
            $0.lastChecked = Date()
            $0.error = error
            if let live { $0.lastKnownIP = live.ips.joined(separator: ", ") }
        }
        return live
    }

    private func parse(_ json: String, expectedName: String) -> (LiveRecord?, String?) {
        struct Response: Decodable {
            struct RecordSet: Decodable {
                struct Value: Decodable { let Value: String }
                let Name: String
                let `Type`: String
                let TTL: Int?
                let ResourceRecords: [Value]?
            }
            let ResourceRecordSets: [RecordSet]
        }
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return (nil, "Could not read the Route 53 response")
        }
        // Route 53 returns the NEXT record when there is no exact match, so check the name and type.
        guard let set = response.ResourceRecordSets.first,
              DNSName.normalize(set.Name) == DNSName.normalize(expectedName),
              set.Type == "A" else {
            return (nil, "Record not found in Route 53")
        }
        guard let ttl = set.TTL, let values = set.ResourceRecords, !values.isEmpty else {
            return (nil, "Alias records are not supported")
        }
        return (LiveRecord(ips: values.map(\.Value), ttl: ttl), nil)
    }

    // MARK: - Update Flow

    /// Validate the new IP and read the live record.
    /// Returns a change to confirm, or nil if invalid, missing, or already up to date.
    func prepareChange(zone: HostedZone, record: DNSRecord, newIP rawIP: String, source: String) async -> PendingDNSChange? {
        let newIP = rawIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard IPv4Address(newIP) != nil, newIP.split(separator: ".").count == 4 else {
            alertQueue?.enqueue(title: "Invalid IP", message: "'\(newIP)' is not a valid IPv4 address.")
            return nil
        }

        busy[record.id] = true
        defer { busy[record.id] = false }

        guard let live = await readLive(zone: zone, record: record) else {
            let message = zones.first(where: { $0.id == zone.id })?
                .records.first(where: { $0.id == record.id })?.error ?? "Could not read the record"
            alertQueue?.enqueue(title: "Can't Update \(record.name)", message: message)
            return nil
        }

        if live.ips == [newIP] {
            toastQueue?.enqueue(message: "\(record.name) is already \(newIP)", icon: "checkmark.circle")
            return nil
        }

        return PendingDNSChange(zone: zone, record: record, oldIP: live.ips.joined(separator: ", "),
                                newIP: newIP, ttl: live.ttl, source: source)
    }

    /// Fetch the linked EC2 instance's latest IP (also refreshes the EC2 module's cache), then prepare the change.
    func prepareChangeFromEC2(zone: HostedZone, record: DNSRecord) async -> PendingDNSChange? {
        guard let (group, instance) = linkedInstance(for: record) else {
            alertQueue?.enqueue(title: "No Linked Instance", message: "The linked EC2 instance no longer exists. Edit the record to link it again.")
            return nil
        }
        busy[record.id] = true
        let result = await EC2ManagerState.shared.manager.refreshPublicIP(group: group, instance: instance)
        busy[record.id] = false

        guard let ip = result.ip else {
            alertQueue?.enqueue(title: "Can't Get IP for \(instance.name)", message: result.error ?? "Unknown error")
            return nil
        }
        return await prepareChange(zone: zone, record: record, newIP: ip, source: "EC2: \(instance.name)")
    }

    /// UPSERT the A record with the new IP. Keeps the live TTL. Logs the result.
    func apply(_ change: PendingDNSChange) async {
        busy[change.record.id] = true
        defer { busy[change.record.id] = false }

        let batch: [String: Any] = [
            "Comment": "DevDash IP update (\(change.source))",
            "Changes": [[
                "Action": "UPSERT",
                "ResourceRecordSet": [
                    "Name": change.record.name,
                    "Type": "A",
                    "TTL": change.ttl,
                    "ResourceRecords": [["Value": change.newIP]]
                ]
            ]]
        ]
        let batchJSON = (try? JSONSerialization.data(withJSONObject: batch)).map { String(decoding: $0, as: UTF8.self) } ?? ""

        let (envOrNil, envError) = await awsEnvironment(profile: change.zone.awsProfile)
        let success: Bool
        let error: String?
        if let env = envOrNil {
            let args = ["route53", "change-resource-record-sets",
                        "--hosted-zone-id", change.zone.zoneId,
                        "--change-batch", batchJSON,
                        "--output", "json"]
            let result = await ShellCommand.run("aws", args, env: env)
            success = result.exitCode == 0
            error = success ? nil : (result.stderr.isEmpty ? "aws exited with \(result.exitCode)" : result.stderr)
        } else {
            (success, error) = (false, envError)
        }

        addLog(IPChangeLogEntry(zoneId: change.zone.id, recordId: change.record.id,
                                zoneName: change.zone.name, recordName: change.record.name,
                                oldIP: change.oldIP, newIP: change.newIP, source: change.source,
                                success: success, error: error))

        mutateRecord(change.zone.id, change.record.id) {
            $0.lastChecked = Date()
            $0.error = error
            if success { $0.lastKnownIP = change.newIP }
        }

        if success {
            toastQueue?.enqueue(message: "\(change.record.name) → \(change.newIP) submitted. Live in about 60s.")
        } else {
            alertQueue?.enqueue(title: "Update Failed", message: error ?? "Unknown error")
        }
    }

    // MARK: - Change Log

    private func addLog(_ entry: IPChangeLogEntry) {
        changeLog.insert(entry, at: 0)
        if changeLog.count > maxLogEntries {
            changeLog.removeLast(changeLog.count - maxLogEntries)
        }
        saveLog()
    }

    // MARK: - Import / Export

    /// Export zones and records. Cached Route 53 values and history are left out.
    func exportZones() {
        let clean = zones.map { zone -> HostedZone in
            var z = zone
            z.records = zone.records.map { DNSRecord(id: $0.id, name: $0.name, link: $0.link) }
            return z
        }
        ImportExportManager.shared.exportJSON(clean, defaultFileName: "route53-zones.json", title: "Export Route 53 Zones") { [weak self] result in
            switch result {
            case .success: self?.toastQueue?.enqueue(message: "Route 53 zones exported")
            case .failure(let error):
                if case .userCancelled = error { return }
                self?.alertQueue?.enqueue(title: "Export Failed", message: error.localizedDescription)
            }
        }
    }

    /// Import zones. Matches zones by zone ID and records by name. Adds and updates, never deletes.
    func importZones() {
        ImportExportManager.shared.importJSON(HostedZone.self, title: "Import Route 53 Zones") { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let imported):
                    let (added, updated) = self.merge(imported)
                    self.saveZones()
                    self.toastQueue?.enqueue(message: "Imported \(added) new, updated \(updated)")
                case .failure(let error):
                    if case .userCancelled = error { return }
                    self.alertQueue?.enqueue(title: "Import Failed", message: error.localizedDescription)
                }
            }
        }
    }

    /// Merge imported zones into `zones`. Returns counts of new and updated zones + records.
    private func merge(_ imported: [HostedZone]) -> (added: Int, updated: Int) {
        var added = 0, updated = 0
        for zone in imported {
            let zoneId = DNSName.normalizeZoneId(zone.zoneId)
            guard let z = zones.firstIndex(where: { $0.zoneId == zoneId }) else {
                var new = HostedZone(name: DNSName.normalize(zone.name), zoneId: zoneId, awsProfile: zone.awsProfile)
                new.records = zone.records.map { DNSRecord(name: DNSName.normalize($0.name), link: $0.link) }
                zones.append(new)
                added += 1 + new.records.count
                continue
            }
            if zones[z].awsProfile != zone.awsProfile || zones[z].name != DNSName.normalize(zone.name) {
                zones[z].awsProfile = zone.awsProfile
                zones[z].name = DNSName.normalize(zone.name)
                updated += 1
            }
            for record in zone.records {
                let name = DNSName.normalize(record.name)
                if let r = zones[z].records.firstIndex(where: { DNSName.normalize($0.name) == name }) {
                    if zones[z].records[r].link != record.link {
                        zones[z].records[r].link = record.link
                        updated += 1
                    }
                } else {
                    zones[z].records.append(DNSRecord(name: name, link: record.link))
                    added += 1
                }
            }
        }
        return (added, updated)
    }

    // MARK: - Backup

    func exportBackupData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Route53Backup(zones: zones, changeLog: changeLog))
    }
}
