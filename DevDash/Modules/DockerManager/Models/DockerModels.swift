//
//  DockerModels.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import Foundation

// MARK: - Container Engine

/// Which CLI runs a container: Docker (on Colima) or Apple's `container`.
enum ContainerEngine: String, Codable, CaseIterable, Identifiable {
    // Order sets the sidebar and picker order
    case apple
    case docker

    var id: String { rawValue }

    /// CLI tool name
    var cli: String {
        switch self {
        case .docker: return "docker"
        case .apple: return "container"
        }
    }

    /// Name of the engine host shown in the sidebar
    var hostName: String {
        switch self {
        case .docker: return "Colima"
        case .apple: return "Apple Containers"
        }
    }

    var hostDescription: String {
        switch self {
        case .docker: return "Docker runtime engine for macOS"
        case .apple: return "Apple's native container runtime (container CLI)"
        }
    }

    /// Command line to start / stop / check the engine host
    var statusArgs: (tool: String, args: [String]) {
        switch self {
        // One JSON line per profile. Says whether an instance exists and its specs.
        case .docker: return ("colima", ["list", "--json"])
        case .apple: return ("container", ["system", "status"])
        }
    }

    var startArgs: (tool: String, args: [String]) {
        switch self {
        case .docker: return ("colima", ["start"])
        case .apple: return ("container", ["system", "start"])
        }
    }

    var stopArgs: (tool: String, args: [String]) {
        switch self {
        case .docker: return ("colima", ["stop"])
        case .apple: return ("container", ["system", "stop"])
        }
    }
}

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
    var engine: ContainerEngine?   // nil = docker (configs saved before engines existed)

    var resolvedEngine: ContainerEngine { engine ?? .docker }

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
        maxLogLines: Int? = 1000,
        engine: ContainerEngine = .docker
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
        self.engine = engine
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
    let engine: ContainerEngine
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
    let engine: ContainerEngine
    let repository: String
    let tag: String
    let imageId: String // Docker image ID
    let size: String
    let createdAt: Date?
}

// MARK: - Engine Info (Lightweight ViewModel)

struct EngineInfo {
    let isRunning: Bool
    let processingAction: ServiceAction?
    var isSetUp: Bool = true      // false = Colima has no instance yet
}

/// The default Colima instance, from `colima list --json`
// ponytail: default profile only. Add a profile picker if you run several.
struct ColimaInstance: Decodable, Equatable {
    let name: String
    let status: String
    let cpus: Int?
    let memory: Double?
    let disk: Double?
    let runtime: String?

    var isRunning: Bool { status.lowercased() == "running" }
    // ponytail: unit not checked against a live instance. Bytes when large, else GiB.
    var memoryGiB: Int? { memory.map(Self.gib) }
    var diskGiB: Int? { disk.map(Self.gib) }
    private static func gib(_ v: Double) -> Int { Int((v > 4096 ? v / 1_073_741_824 : v).rounded()) }

    static func parse(_ output: String) -> ColimaInstance? {
        output.split(whereSeparator: \.isNewline)
            .compactMap { try? JSONDecoder().decode(ColimaInstance.self, from: Data($0.utf8)) }
            .first { $0.name == "default" }
    }
}
