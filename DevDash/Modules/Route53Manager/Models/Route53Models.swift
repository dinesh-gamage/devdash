//
//  Route53Models.swift
//  DevDash
//

import Foundation

// MARK: - Hosted Zone

/// A Route 53 hosted zone. Holds only the records the user added by hand.
struct HostedZone: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String        // e.g. "lucyday.io"
    var zoneId: String      // e.g. "Z0123456789ABC"
    var awsProfile: String
    var records: [DNSRecord]

    init(id: UUID = UUID(), name: String, zoneId: String, awsProfile: String, records: [DNSRecord] = []) {
        self.id = id
        self.name = name
        self.zoneId = zoneId
        self.awsProfile = awsProfile
        self.records = records
    }
}

// MARK: - DNS Record

/// One A record to keep updated. Only its IP is ever changed.
struct DNSRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String               // e.g. "*.v5.lucyday.io"
    var link: InstanceLink?        // Optional EC2 instance to take the IP from
    var lastKnownIP: String?       // Last value read from Route 53
    var lastChecked: Date?
    var error: String?

    init(id: UUID = UUID(), name: String, link: InstanceLink? = nil) {
        self.id = id
        self.name = name
        self.link = link
    }
}

/// Points to an instance in the EC2 Manager module. Resolved when used.
struct InstanceLink: Codable, Hashable {
    let groupId: UUID
    let instanceId: UUID
}

// MARK: - Change Log

struct IPChangeLogEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let zoneId: UUID
    let recordId: UUID
    let zoneName: String
    let recordName: String
    let oldIP: String?
    let newIP: String
    let source: String      // "Manual" or "EC2: <instance name>"
    let success: Bool
    let error: String?

    init(zoneId: UUID, recordId: UUID, zoneName: String, recordName: String, oldIP: String?, newIP: String, source: String, success: Bool, error: String?) {
        self.id = UUID()
        self.date = Date()
        self.zoneId = zoneId
        self.recordId = recordId
        self.zoneName = zoneName
        self.recordName = recordName
        self.oldIP = oldIP
        self.newIP = newIP
        self.source = source
        self.success = success
        self.error = error
    }
}

// MARK: - Runtime (not persisted)

/// A checked change waiting for the user to confirm.
struct PendingDNSChange: Identifiable {
    let id = UUID()
    let zone: HostedZone
    let record: DNSRecord
    let oldIP: String
    let newIP: String
    let ttl: Int
    let source: String
}

/// Backup payload for this module.
struct Route53Backup: Codable {
    let zones: [HostedZone]
    let changeLog: [IPChangeLogEntry]
}

// MARK: - Name Helpers

enum DNSName {
    /// Lowercase, no trailing dot, and `\052` (how Route 53 returns `*`) turned back into `*`.
    nonisolated static func normalize(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        n = n.replacingOccurrences(of: "\\052", with: "*")
        while n.hasSuffix(".") { n.removeLast() }
        return n
    }

    /// Accepts "Z123", "/hostedzone/Z123" or "hostedzone/Z123". Returns "Z123".
    nonisolated static func normalizeZoneId(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: "/").last.map(String.init)?.uppercased() ?? ""
    }

    nonisolated static func isValidZoneId(_ id: String) -> Bool {
        id.range(of: "^Z[A-Z0-9]{5,}$", options: .regularExpression) != nil
    }

    /// The record must be the zone apex or sit under it.
    nonisolated static func record(_ record: String, belongsTo zone: String) -> Bool {
        let r = normalize(record), z = normalize(zone)
        return !z.isEmpty && (r == z || r.hasSuffix("." + z))
    }
}
