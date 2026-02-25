//
//  EditContainerView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

struct EditContainerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: DockerManager
    let container: ContainerRuntime

    @State private var name: String
    @State private var image: String
    @State private var ports: [PortMapping]
    @State private var volumes: [VolumeMount]
    @State private var envVars: [EnvVar]
    @State private var network: String
    @State private var command: String
    @State private var restartPolicy: String
    @State private var cpuLimit: String
    @State private var memoryLimit: String
    @State private var additionalParams: [AdditionalParam]
    @State private var maxLogLines: String

    init(manager: DockerManager, container: ContainerRuntime) {
        self.manager = manager
        self.container = container

        _name = State(initialValue: container.config.name)
        _image = State(initialValue: container.config.image)
        _ports = State(initialValue: container.config.ports)
        _volumes = State(initialValue: container.config.volumes)
        _envVars = State(initialValue: container.config.environment.map { EnvVar(key: $0.key, value: $0.value) })
        _network = State(initialValue: container.config.network ?? "")
        _command = State(initialValue: container.config.command ?? "")
        _restartPolicy = State(initialValue: container.config.restartPolicy ?? "no")
        _cpuLimit = State(initialValue: container.config.cpuLimit ?? "")
        _memoryLimit = State(initialValue: container.config.memoryLimit ?? "")
        _additionalParams = State(initialValue: container.config.additionalParams)
        _maxLogLines = State(initialValue: "\(container.config.maxLogLines ?? 1000)")
    }

    var body: some View {
        NavigationStack {
            ContainerFormContent(
                name: $name,
                image: $image,
                ports: $ports,
                volumes: $volumes,
                envVars: $envVars,
                network: $network,
                command: $command,
                restartPolicy: $restartPolicy,
                cpuLimit: $cpuLimit,
                memoryLimit: $memoryLimit,
                additionalParams: $additionalParams,
                maxLogLines: $maxLogLines
            )
            .navigationTitle("Edit Container")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveContainer() }
                        .disabled(name.isEmpty || image.isEmpty)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }

    private func saveContainer() {
        let config = ContainerConfig(
            id: container.config.id,
            name: name,
            image: image,
            ports: ports.filter { !$0.hostPort.isEmpty && !$0.containerPort.isEmpty },
            volumes: volumes.filter { !$0.hostPath.isEmpty && !$0.containerPath.isEmpty },
            environment: Dictionary(uniqueKeysWithValues: envVars.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) }),
            network: network.isEmpty ? nil : network,
            command: command.isEmpty ? nil : command,
            restartPolicy: restartPolicy == "no" ? nil : restartPolicy,
            cpuLimit: cpuLimit.isEmpty ? nil : cpuLimit,
            memoryLimit: memoryLimit.isEmpty ? nil : memoryLimit,
            additionalParams: additionalParams.filter { !$0.flag.isEmpty },
            maxLogLines: Int(maxLogLines)
        )

        manager.updateContainer(container, with: config)
        dismiss()
    }
}
