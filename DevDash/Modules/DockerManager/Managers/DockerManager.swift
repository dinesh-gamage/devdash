//
//  DockerManager.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class DockerManager: ObservableObject {
    // Public - lightweight lists for consumers
    @Published var containersList: [ContainerInfo] = []
    @Published var images: [ContainerEngine: [ImageInfo]] = [:]
    /// Containers found in an engine that DevDash doesn't track yet
    @Published var discovered: [ContainerEngine: [ContainerConfig]] = [:]
    @Published private(set) var scanning: Set<ContainerEngine> = []
    @Published private(set) var isLoading = false

    // Private - full runtimes with logs/processes
    private var runtimes: [UUID: ContainerRuntime] = [:]
    private var cancellables = Set<AnyCancellable>()

    private weak var alertQueue: AlertQueue?
    private weak var toastQueue: ToastQueue?

    init(alertQueue: AlertQueue? = nil, toastQueue: ToastQueue? = nil) {
        self.alertQueue = alertQueue
        self.toastQueue = toastQueue
        loadContainers()
    }

    func loadContainers() {
        if let configs: [ContainerConfig] = StorageManager.shared.load(forKey: "containers") {
            runtimes = Dictionary(uniqueKeysWithValues: configs.map { config in
                let runtime = ContainerRuntime(config: config)
                subscribeToRuntime(runtime)
                return (config.id, runtime)
            })
        } else {
            runtimes = [:]
        }
        // Initial sync without status check
        refreshContainersListSync()
    }

    func saveContainers() {
        let configs = runtimes.values.map { $0.config }
        StorageManager.shared.save(configs, forKey: "containers")
    }

    // MARK: - Runtime Access

    /// Get full runtime for detail view (on-demand)
    func getRuntime(id: UUID) -> ContainerRuntime? {
        return runtimes[id]
    }

    /// Get all runtimes (private - use containersList for views)
    private var containers: [ContainerRuntime] {
        return Array(runtimes.values)
    }

    // MARK: - List Refresh

    /// Refresh lightweight containersList from runtimes (sync - just maps data, no checkStatus)
    private func refreshContainersListSync() {
        containersList = runtimes.values.map { runtime in
            ContainerInfo(
                id: runtime.id,
                name: runtime.config.name,
                image: runtime.config.image,
                engine: runtime.config.resolvedEngine,
                status: runtime.status,
                dockerId: runtime.dockerId,
                ports: runtime.config.ports,
                createdAt: nil,
                processingAction: runtime.processingAction
            )
        }.sorted { $0.name < $1.name }
    }

    /// Refresh lightweight containersList from runtimes (with status check - use for manual refresh only)
    func refreshContainersList() async {
        // Check status for all containers first
        await withTaskGroup(of: Void.self) { group in
            for runtime in runtimes.values {
                group.addTask {
                    await runtime.checkStatus()
                }
            }
        }

        // Build list
        refreshContainersListSync()
    }

    /// Containers of one engine
    func containers(for engine: ContainerEngine) -> [ContainerInfo] {
        containersList.filter { $0.engine == engine }
    }

    /// Refresh one engine's images
    func refreshImages(_ engine: ContainerEngine) async {
        let env = ProcessEnvironment.shared.getEnvironment()
        switch engine {
        case .docker:
            let r = await ShellCommand.run("docker", ["images", "--format", "{{.Repository}}|||{{.Tag}}|||{{.ID}}|||{{.Size}}"], env: env)
            images[engine] = r.stdout.split(whereSeparator: \.isNewline).compactMap { line in
                let parts = line.components(separatedBy: "|||")
                guard parts.count == 4, parts[0] != "<none>" else { return nil }
                return ImageInfo(id: "\(parts[0]):\(parts[1])", engine: .docker, repository: parts[0], tag: parts[1],
                                 imageId: parts[2], size: parts[3], createdAt: nil)
            }
        case .apple:
            struct AppleImage: Decodable {
                struct Configuration: Decodable { let name: String }
                struct Variant: Decodable { let size: Int? }
                let id: String
                let configuration: Configuration
                let variants: [Variant]?
            }
            let r = await ShellCommand.run("container", ["image", "list", "--format", "json"], env: env)
            let decoded = (try? JSONDecoder().decode([AppleImage].self, from: Data(r.stdout.utf8))) ?? []
            images[engine] = decoded.map { img in
                // name is "registry/repo:tag"
                let name = img.configuration.name
                let colon = name.lastIndex(of: ":").flatMap { name[$0...].contains("/") ? nil : $0 }
                let repo = colon.map { String(name[..<$0]) } ?? name
                let tag = colon.map { String(name[name.index(after: $0)...]) } ?? "latest"
                // ponytail: size is the largest platform variant, not what is on disk
                let bytes = Int64(img.variants?.compactMap(\.size).max() ?? 0)
                return ImageInfo(id: name, engine: .apple, repository: repo, tag: tag,
                                 imageId: String(img.id.prefix(12)),
                                 size: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), createdAt: nil)
            }
        }
    }

    // MARK: - Scan

    /// Find containers in the engine that DevDash doesn't track (matched by name)
    func scan(_ engine: ContainerEngine) async {
        guard !scanning.contains(engine) else { return }
        scanning.insert(engine)
        defer { scanning.remove(engine) }

        let found = await ContainerScanner.scan(engine)
        let tracked = Set(runtimes.values.filter { $0.config.resolvedEngine == engine }.map(\.config.name))
        discovered[engine] = found.filter { !tracked.contains($0.name) }.sorted { $0.name < $1.name }
    }

    /// Add scanned containers to DevDash. They already exist, so nothing is created.
    func adopt(_ configs: [ContainerConfig]) {
        for config in configs {
            let runtime = ContainerRuntime(config: config)
            subscribeToRuntime(runtime)
            runtimes[config.id] = runtime
            discovered[config.resolvedEngine]?.removeAll { $0.id == config.id }
            Task { await runtime.checkStatus() }
        }
        saveContainers()
        refreshContainersListSync()
        toastQueue?.enqueue(message: configs.count == 1 ? "'\(configs[0].name)' added" : "\(configs.count) containers added")
    }

    /// Subscribe to runtime changes to auto-refresh list (without checkStatus to avoid infinite loop)
    private func subscribeToRuntime(_ runtime: ContainerRuntime) {
        runtime.objectWillChange
            .sink { [weak self] _ in
                self?.refreshContainersListSync()
            }
            .store(in: &cancellables)
    }

    // MARK: - CRUD Operations

    func addContainer(_ config: ContainerConfig) {
        let runtime = ContainerRuntime(config: config)
        subscribeToRuntime(runtime)
        runtimes[config.id] = runtime
        saveContainers()
        refreshContainersListSync()
        toastQueue?.enqueue(message: "'\(config.name)' added")
    }

    func updateContainer(_ container: ContainerRuntime, with newConfig: ContainerConfig) {
        guard runtimes[container.id] != nil else { return }

        // Stop if running
        Task {
            if container.isRunning {
                await container.stop()
            }

            await MainActor.run {
                let updatedRuntime = ContainerRuntime(config: newConfig)
                subscribeToRuntime(updatedRuntime)
                runtimes[container.id] = updatedRuntime
                saveContainers()
                refreshContainersListSync()
                toastQueue?.enqueue(message: "'\(newConfig.name)' updated")
            }
        }
    }

    func deleteContainer(id: UUID) async {
        guard let container = runtimes[id] else { return }

        // Delete from Docker
        await container.delete()

        runtimes.removeValue(forKey: id)
        saveContainers()
        refreshContainersListSync()
    }

    /// Stop tracking a container in DevDash. The container stays in its engine.
    func removeContainer(id: UUID) {
        guard let runtime = runtimes.removeValue(forKey: id) else { return }
        saveContainers()
        refreshContainersListSync()
        toastQueue?.enqueue(message: "'\(runtime.config.name)' removed from DevDash")
        Task { await scan(runtime.config.resolvedEngine) }
    }

    func checkAllContainers() {
        Task {
            await refreshContainersList()
        }
    }

    // MARK: - Image Operations


    func deleteImage(_ imageInfo: ImageInfo) async {
        let args = imageInfo.engine == .docker ? ["rmi", imageInfo.id] : ["image", "delete", imageInfo.id]
        let r = await ShellCommand.run(imageInfo.engine.cli, args, env: ProcessEnvironment.shared.getEnvironment())
        if r.exitCode == 0 {
            toastQueue?.enqueue(message: "Deleted '\(imageInfo.id)'")
        } else {
            alertQueue?.enqueue(title: "Delete Failed", message: r.stderr.isEmpty ? r.stdout : r.stderr)
        }
        await refreshImages(imageInfo.engine)
    }

    // MARK: - Backup Export

    func exportBackupData() async throws -> Data {
        let configs = containers.map { $0.config }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(configs)
    }

    // MARK: - Import/Export

    func exportContainers() {
        Task {
            do {
                try await BiometricAuthManager.shared.authenticate(reason: "Authenticate to export containers")

                let configs = runtimes.values.map { $0.config }
                ImportExportManager.shared.exportJSON(
                    configs,
                    defaultFileName: "containers.json",
                    title: "Export Containers"
                ) { [weak self] result in
                    switch result {
                    case .success:
                        self?.toastQueue?.enqueue(message: "Containers exported successfully")
                    case .failure(let error):
                        if case .userCancelled = error {
                            return
                        }
                        self?.alertQueue?.enqueue(title: "Export Failed", message: error.localizedDescription)
                    }
                }
            } catch {
                await MainActor.run {
                    self.alertQueue?.enqueue(title: "Authentication Required", message: "You must authenticate to export containers")
                }
            }
        }
    }

    func importContainers() {
        isLoading = true

        ImportExportManager.shared.importJSON(
            ContainerConfig.self,
            title: "Import Containers"
        ) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                switch result {
                case .success(let configs):
                    var newCount = 0
                    var updatedCount = 0

                    for config in configs {
                        let trimmedName = config.name.trimmingCharacters(in: .whitespaces)
                        if let existing = self.runtimes.values.first(where: {
                            $0.config.name.trimmingCharacters(in: .whitespaces) == trimmedName
                                && $0.config.resolvedEngine == config.resolvedEngine
                        }) {
                            // Keep the existing id so the list selection stays stable
                            let updated = ContainerConfig(id: existing.id, name: config.name, image: config.image, ports: config.ports,
                                                     volumes: config.volumes, environment: config.environment, network: config.network,
                                                     command: config.command, restartPolicy: config.restartPolicy, cpuLimit: config.cpuLimit,
                                                     memoryLimit: config.memoryLimit, additionalParams: config.additionalParams,
                                                     maxLogLines: config.maxLogLines, engine: config.resolvedEngine)
                            let runtime = ContainerRuntime(config: updated)
                            self.subscribeToRuntime(runtime)
                            self.runtimes[existing.id] = runtime
                            updatedCount += 1
                        } else {
                            let runtime = ContainerRuntime(config: config)
                            self.subscribeToRuntime(runtime)
                            self.runtimes[config.id] = runtime
                            newCount += 1
                        }
                    }

                    self.saveContainers()
                    self.refreshContainersListSync()
                    self.isLoading = false

                    let message: String
                    if newCount > 0 && updatedCount > 0 {
                        message = "Imported \(newCount) new, updated \(updatedCount) existing"
                    } else if newCount > 0 {
                        message = "Imported \(newCount) new container\(newCount == 1 ? "" : "s")"
                    } else if updatedCount > 0 {
                        message = "Updated \(updatedCount) container\(updatedCount == 1 ? "" : "s")"
                    } else {
                        message = "No containers imported"
                    }
                    self.toastQueue?.enqueue(message: message)

                case .failure(let error):
                    self.isLoading = false

                    if case .userCancelled = error {
                        return
                    }
                    self.alertQueue?.enqueue(title: "Import Failed", message: error.localizedDescription)
                }
            }
        }
    }
}
