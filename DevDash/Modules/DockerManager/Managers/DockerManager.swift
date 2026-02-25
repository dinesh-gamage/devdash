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
    @Published var imagesList: [ImageInfo] = []
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
        Task {
            await refreshImagesList()
        }
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

    /// Refresh images list from docker
    func refreshImagesList() async {
        let images = await Task.detached(priority: .userInitiated) { () -> [ImageInfo] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-l", "-c", "docker images --format '{{.Repository}}|||{{.Tag}}|||{{.ID}}|||{{.Size}}'"]
            task.environment = ProcessEnvironment.shared.getEnvironment()

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                var images: [ImageInfo] = []
                for line in output.components(separatedBy: .newlines) {
                    guard !line.isEmpty else { continue }

                    let parts = line.split(separator: "|||").map(String.init)
                    guard parts.count == 4 else { continue }

                    let repository = parts[0]
                    let tag = parts[1]
                    let imageId = parts[2]
                    let size = parts[3]

                    // Skip <none> images
                    guard repository != "<none>" else { continue }

                    images.append(ImageInfo(
                        id: "\(repository):\(tag)",
                        repository: repository,
                        tag: tag,
                        imageId: imageId,
                        size: size,
                        createdAt: nil
                    ))
                }

                return images
            } catch {
                return []
            }
        }.value

        imagesList = images
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

    func deleteContainer(at offsets: IndexSet) {
        let sortedContainers = runtimes.values.sorted { $0.config.name < $1.config.name }

        Task {
            for index in offsets {
                let container = sortedContainers[index]

                // Delete from Docker
                await container.delete()

                await MainActor.run {
                    runtimes.removeValue(forKey: container.id)
                }
            }

            await MainActor.run {
                saveContainers()
                refreshContainersListSync()
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

    func checkAllContainers() {
        Task {
            await refreshContainersList()
        }
    }

    // MARK: - Image Operations


    func deleteImage(_ imageInfo: ImageInfo) async {
        let output = await Task.detached(priority: .userInitiated) { () -> String in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-l", "-c", "docker rmi \(imageInfo.id)"]
            task.environment = ProcessEnvironment.shared.getEnvironment()

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                return "Error: \(error.localizedDescription)"
            }
        }.value

        if output.contains("Untagged") || output.contains("Deleted") {
            toastQueue?.enqueue(message: "Deleted '\(imageInfo.id)'")
        } else {
            alertQueue?.enqueue(title: "Delete Failed", message: output)
        }

        await refreshImagesList()
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
                        }) {
                            let runtime = ContainerRuntime(config: config)
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
