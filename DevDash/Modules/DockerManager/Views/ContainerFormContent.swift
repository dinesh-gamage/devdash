//
//  ContainerFormContent.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

struct ContainerFormContent: View {
    @Binding var engine: ContainerEngine
    @Binding var name: String
    @Binding var image: String
    @Binding var ports: [PortMapping]
    @Binding var volumes: [VolumeMount]
    @Binding var envVars: [EnvVar]
    @Binding var network: String
    @Binding var command: String
    @Binding var restartPolicy: String
    @Binding var cpuLimit: String
    @Binding var memoryLimit: String
    @Binding var additionalParams: [AdditionalParam]
    @Binding var maxLogLines: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Basic Info
                FormSection(title: "Basic Info") {
                    FormField(label: "Engine") {
                        Picker("", selection: $engine) {
                            ForEach(ContainerEngine.allCases) { Text($0.hostName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    FormField(label: "Container Name") {
                        TextField("my-container", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    FormField(label: "Image") {
                        TextField("nginx:latest", text: $image)
                            .textFieldStyle(.roundedBorder)
                    }
                    FormField(label: "Command Override (optional)", hint: "Override the default image command") {
                        TextField("/bin/sh -c 'echo hello'", text: $command)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Port Mappings
                FormSection(title: "Port Mappings") {
                    ForEach($ports) { $port in
                        HStack(spacing: 8) {
                            TextField("Host", text: $port.hostPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 100)
                            Text(":")
                                .foregroundColor(.secondary)
                            TextField("Container", text: $port.containerPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 100)
                            Picker("", selection: $port.protocol) {
                                Text("tcp").tag("tcp")
                                Text("udp").tag("udp")
                            }
                            .frame(width: 80)
                            Button(action: { ports.removeAll { $0.id == port.id } }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button(action: { ports.append(PortMapping(hostPort: "", containerPort: "")) }) {
                        Label("Add Port Mapping", systemImage: "plus.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                // Volume Mounts
                FormSection(title: "Volume Mounts") {
                    ForEach($volumes) { $volume in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                TextField("Host Path", text: $volume.hostPath)
                                    .textFieldStyle(.roundedBorder)
                                Text(":")
                                    .foregroundColor(.secondary)
                                TextField("Container Path", text: $volume.containerPath)
                                    .textFieldStyle(.roundedBorder)
                                Button(action: { volumes.removeAll { $0.id == volume.id } }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            Toggle("Read Only", isOn: $volume.readOnly)
                                .toggleStyle(.checkbox)
                                .font(.callout)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                    }
                    Button(action: { volumes.append(VolumeMount(hostPath: "", containerPath: "")) }) {
                        Label("Add Volume Mount", systemImage: "plus.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                // Environment Variables
                FormSection(title: "Environment Variables") {
                    ForEach($envVars) { $envVar in
                        HStack(spacing: 8) {
                            TextField("KEY", text: $envVar.key)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 160)
                            TextField("value", text: $envVar.value)
                                .textFieldStyle(.roundedBorder)
                            Button(action: { envVars.removeAll { $0.id == envVar.id } }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button(action: { envVars.append(EnvVar(key: "", value: "")) }) {
                        Label("Add Variable", systemImage: "plus.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                // Advanced Options
                FormSection(title: "Advanced Options") {
                    FormField(label: "Network", hint: "Network name (e.g., bridge, host). Leave empty for the default.") {
                        TextField("bridge", text: $network)
                            .textFieldStyle(.roundedBorder)
                    }
                    // Apple's container CLI has no restart policy
                    if engine == .docker {
                        FormField(label: "Restart Policy") {
                            Picker("", selection: $restartPolicy) {
                                Text("No").tag("no")
                                Text("Always").tag("always")
                                Text("On Failure").tag("on-failure")
                                Text("Unless Stopped").tag("unless-stopped")
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    HStack(spacing: 12) {
                        FormField(label: "CPU Limit", hint: "e.g., 1.5") {
                            TextField("1.0", text: $cpuLimit)
                                .textFieldStyle(.roundedBorder)
                        }
                        FormField(label: "Memory Limit", hint: engine == .docker ? "e.g., 512m, 1g" : "e.g., 512M, 4G") {
                            TextField("512m", text: $memoryLimit)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    FormField(label: "Max Log Lines", hint: "Default 1000") {
                        TextField("1000", text: $maxLogLines)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                    }
                }

                // Additional Parameters
                FormSection(title: "Additional Parameters") {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("Add extra \(engine.cli) create flags (e.g., --privileged, --cap-add SYS_ADMIN)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 4)

                    ForEach($additionalParams) { $param in
                        HStack(spacing: 8) {
                            TextField("--flag", text: $param.flag)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 160)
                            TextField("value (optional)", text: $param.value)
                                .textFieldStyle(.roundedBorder)
                            Button(action: { additionalParams.removeAll { $0.id == param.id } }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button(action: { additionalParams.append(AdditionalParam(flag: "", value: "")) }) {
                        Label("Add Parameter", systemImage: "plus.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
            .padding(20)
        }
    }
}
