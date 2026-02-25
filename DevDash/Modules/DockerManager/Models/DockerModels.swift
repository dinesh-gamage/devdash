//
//  DockerModels.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import Foundation

// MARK: - Port Mapping

struct PortMapping: Codable, Identifiable, Equatable {
    let id: UUID
    var hostPort: String
    var containerPort: String
    var `protocol`: String // "tcp" or "udp"

    init(id: UUID = UUID(), hostPort: String, containerPort: String, protocol: String = "tcp") {
        self.id = id
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.`protocol` = `protocol`
    }

    var dockerFormat: String {
        "\(hostPort):\(containerPort)/\(`protocol`)"
    }
}

// MARK: - Volume Mount

struct VolumeMount: Codable, Identifiable, Equatable {
    let id: UUID
    var hostPath: String
    var containerPath: String
    var readOnly: Bool

    init(id: UUID = UUID(), hostPath: String, containerPath: String, readOnly: Bool = false) {
        self.id = id
        self.hostPath = hostPath
        self.containerPath = containerPath
        self.readOnly = readOnly
    }

    var dockerFormat: String {
        readOnly ? "\(hostPath):\(containerPath):ro" : "\(hostPath):\(containerPath)"
    }
}

// MARK: - Additional Parameter

struct AdditionalParam: Codable, Identifiable, Equatable {
    let id: UUID
    var flag: String
    var value: String

    init(id: UUID = UUID(), flag: String, value: String = "") {
        self.id = id
        self.flag = flag
        self.value = value
    }
}

// MARK: - Container Configuration

struct ContainerConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var image: String
    var ports: [PortMapping]
    var volumes: [VolumeMount]
    var environment: [String: String]
    var network: String?
    var command: String?
    var restartPolicy: String? // "no", "always", "on-failure", "unless-stopped"
    var cpuLimit: String? // e.g., "1.5"
    var memoryLimit: String? // e.g., "512m"
    var additionalParams: [AdditionalParam]
    var maxLogLines: Int?

    init(
        id: UUID = UUID(),
        name: String,
        image: String,
        ports: [PortMapping] = [],
        volumes: [VolumeMount] = [],
        environment: [String: String] = [:],
        network: String? = nil,
        command: String? = nil,
        restartPolicy: String? = nil,
        cpuLimit: String? = nil,
        memoryLimit: String? = nil,
        additionalParams: [AdditionalParam] = [],
        maxLogLines: Int? = 1000
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.ports = ports
        self.volumes = volumes
        self.environment = environment
        self.network = network
        self.command = command
        self.restartPolicy = restartPolicy
        self.cpuLimit = cpuLimit
        self.memoryLimit = memoryLimit
        self.additionalParams = additionalParams
        self.maxLogLines = maxLogLines
    }
}

// MARK: - Container Action

enum ContainerAction: Equatable {
    case starting
    case stopping
    case restarting
    case deleting
    case creating
}

// MARK: - Container Info (Lightweight ViewModel)

struct ContainerInfo: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let image: String
    let status: ContainerStatus
    let dockerId: String? // Docker's actual container ID
    let ports: [PortMapping]
    let createdAt: Date?
    let processingAction: ContainerAction?

    enum ContainerStatus: String, Equatable, Hashable {
        case running = "running"
        case stopped = "exited"
        case created = "created"
        case paused = "paused"
        case unknown = "unknown"
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Image Info

struct ImageInfo: Identifiable, Equatable, Hashable {
    let id: String // Repository:tag
    let repository: String
    let tag: String
    let imageId: String // Docker image ID
    let size: String
    let createdAt: Date?
}

// MARK: - Colima Info (Lightweight ViewModel)

struct ColimaInfo {
    let isRunning: Bool
    let processingAction: ServiceAction?
}
