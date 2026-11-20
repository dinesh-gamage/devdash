//
//  ContainerScanner.swift
//  DevDash
//
//  Reads containers that exist in an engine and maps them to ContainerConfig,
//  so containers created outside DevDash can be added to it.
//

import Foundation

enum ContainerScanner {

    /// All containers the engine knows about, as configs. Empty if the engine can't be reached.
    nonisolated static func scan(_ engine: ContainerEngine) async -> [ContainerConfig] {
        let env = ProcessEnvironment.shared.getEnvironment()
        switch engine {
        case .apple:
            let list = await ShellCommand.run("container", ["list", "--all", "--format", "json"], env: env)
            let images = await ShellCommand.run("container", ["image", "list", "--format", "json"], env: env)
            guard list.exitCode == 0 else { return [] }
            return parseApple(list.stdout, imagesJSON: images.stdout)

        case .docker:
            let ids = await ShellCommand.run("docker", ["ps", "-a", "-q"], env: env)
            let idList = ids.stdout.split(whereSeparator: \.isNewline).map(String.init)
            guard ids.exitCode == 0, !idList.isEmpty else { return [] }
            let inspect = await ShellCommand.run("docker", ["inspect"] + idList, env: env)
            let imageNames = Set(parseDockerImageNames(inspect.stdout))
            let imageInspect = await ShellCommand.run("docker", ["image", "inspect"] + imageNames.sorted(), env: env)
            return parseDocker(inspect.stdout, imagesJSON: imageInspect.stdout)
        }
    }

    // MARK: - Apple (`container list --all --format json`)

    private struct AppleContainer: Decodable {
        struct Configuration: Decodable {
            struct Image: Decodable { let reference: String }
            struct Port: Decodable { let hostPort: Int; let containerPort: Int; let proto: String? }
            struct Mount: Decodable { let source: String; let destination: String; let options: [String]? }
            struct InitProcess: Decodable { let arguments: [String]?; let environment: [String]? }
            struct Resources: Decodable { let cpus: Int?; let memoryInBytes: Int? }
            struct Network: Decodable { let network: String }
            let id: String
            let image: Image
            let publishedPorts: [Port]?
            let mounts: [Mount]?
            let initProcess: InitProcess?
            let resources: Resources?
            let networks: [Network]?
        }
        let configuration: Configuration
    }

    private struct AppleImage: Decodable {
        struct Configuration: Decodable { let name: String }
        struct Variant: Decodable {
            struct Outer: Decodable { let config: Inner? }
            struct Inner: Decodable { let Env: [String]?; let Cmd: [String]? }
            let config: Outer?
        }
        let configuration: Configuration
        let variants: [Variant]?
    }

    nonisolated static func parseApple(_ json: String, imagesJSON: String) -> [ContainerConfig] {
        guard let containers = try? JSONDecoder().decode([AppleContainer].self, from: Data(json.utf8)) else { return [] }
        let images = (try? JSONDecoder().decode([AppleImage].self, from: Data(imagesJSON.utf8))) ?? []

        return containers.map { item in
            let c = item.configuration
            let image = images.first { $0.configuration.name == c.image.reference }
            let inner = image?.variants?.compactMap { $0.config?.config }
            let defaultEnv = Set(inner?.flatMap { $0.Env ?? [] } ?? [])
            let defaultCmd = inner?.first?.Cmd

            let args = c.initProcess?.arguments ?? []
            let network = c.networks?.first?.network

            return ContainerConfig(
                name: c.id,
                image: c.image.reference,
                ports: (c.publishedPorts ?? []).map {
                    PortMapping(hostPort: "\($0.hostPort)", containerPort: "\($0.containerPort)", protocol: $0.proto ?? "tcp")
                },
                volumes: (c.mounts ?? []).map {
                    VolumeMount(hostPath: $0.source, containerPath: $0.destination, readOnly: $0.options?.contains("ro") == true)
                },
                environment: userEnv(c.initProcess?.environment ?? [], defaults: defaultEnv),
                network: network == "default" ? nil : network,
                command: args.isEmpty || args == defaultCmd ? nil : args.joined(separator: " "),
                cpuLimit: c.resources?.cpus.map(String.init),
                memoryLimit: c.resources?.memoryInBytes.map { "\($0 / 1_048_576)M" },
                engine: .apple
            )
        }
    }

    // MARK: - Docker (`docker inspect`)

    private struct DockerContainer: Decodable {
        struct Config: Decodable { let Image: String; let Env: [String]?; let Cmd: [String]? }
        struct HostConfig: Decodable {
            struct Binding: Decodable { let HostPort: String? }
            struct Restart: Decodable { let Name: String? }
            let PortBindings: [String: [Binding]?]?
            let NanoCpus: Int?
            let Memory: Int?
            let RestartPolicy: Restart?
            let NetworkMode: String?
        }
        struct Mount: Decodable { let Source: String?; let Destination: String; let RW: Bool? }
        let Name: String
        let Config: Config
        let HostConfig: HostConfig?
        let Mounts: [Mount]?
    }

    private struct DockerImage: Decodable {
        struct Config: Decodable { let Env: [String]?; let Cmd: [String]? }
        let RepoTags: [String]?
        let Config: Config?
    }

    nonisolated static func parseDockerImageNames(_ json: String) -> [String] {
        ((try? JSONDecoder().decode([DockerContainer].self, from: Data(json.utf8))) ?? []).map(\.Config.Image)
    }

    nonisolated static func parseDocker(_ json: String, imagesJSON: String) -> [ContainerConfig] {
        guard let containers = try? JSONDecoder().decode([DockerContainer].self, from: Data(json.utf8)) else { return [] }
        let images = (try? JSONDecoder().decode([DockerImage].self, from: Data(imagesJSON.utf8))) ?? []

        return containers.map { c in
            let image = images.first { $0.RepoTags?.contains(c.Config.Image) == true }
            let host = c.HostConfig
            let ports: [PortMapping] = (host?.PortBindings ?? [:]).sorted { $0.key < $1.key }.flatMap { key, bindings in
                // key is "80/tcp"
                let parts = key.split(separator: "/").map(String.init)
                return (bindings ?? []).compactMap { b in
                    b.HostPort.map { PortMapping(hostPort: $0, containerPort: parts[0], protocol: parts.count > 1 ? parts[1] : "tcp") }
                }
            }
            let network = host?.NetworkMode
            let restart = host?.RestartPolicy?.Name
            let cmd = c.Config.Cmd ?? []

            return ContainerConfig(
                name: String(c.Name.drop(while: { $0 == "/" })),
                image: c.Config.Image,
                ports: ports,
                volumes: (c.Mounts ?? []).compactMap { m in
                    m.Source.map { VolumeMount(hostPath: $0, containerPath: m.Destination, readOnly: m.RW == false) }
                },
                environment: userEnv(c.Config.Env ?? [], defaults: Set(image?.Config?.Env ?? [])),
                network: network == nil || network == "default" || network == "bridge" ? nil : network,
                command: cmd.isEmpty || cmd == image?.Config?.Cmd ? nil : cmd.joined(separator: " "),
                restartPolicy: restart == nil || restart == "no" || restart == "" ? nil : restart,
                cpuLimit: host?.NanoCpus.flatMap { $0 > 0 ? String(Double($0) / 1e9) : nil },
                memoryLimit: host?.Memory.flatMap { $0 > 0 ? "\($0 / 1_048_576)m" : nil },
                engine: .docker
            )
        }
    }

    // MARK: - Helpers

    /// "KEY=value" list → dictionary, dropping variables that come from the image unchanged (PATH etc.)
    nonisolated static func userEnv(_ env: [String], defaults: Set<String>) -> [String: String] {
        var result: [String: String] = [:]
        for entry in env where !defaults.contains(entry) {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            result[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return result
    }
}
