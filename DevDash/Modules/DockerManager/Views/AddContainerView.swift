//
//  AddContainerView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

struct AddContainerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: DockerManager

    @State private var name = ""
    @State private var image = ""
    @State private var ports: [PortMapping] = []
    @State private var volumes: [VolumeMount] = []
    @State private var envVars: [EnvVar] = []
    @State private var network = ""
    @State private var command = ""
    @State private var restartPolicy = "no"
    @State private var cpuLimit = ""
    @State private var memoryLimit = ""
    @State private var additionalParams: [AdditionalParam] = []
    @State private var maxLogLines = "1000"

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
            .navigationTitle("Add Container")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addContainer() }
                        .disabled(name.isEmpty || image.isEmpty)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }

    private func addContainer() {
        let config = ContainerConfig(
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

        manager.addContainer(config)
        dismiss()
    }
}
