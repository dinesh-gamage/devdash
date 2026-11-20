//
//  FormComponents.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI
import AppKit

// MARK: - Environment Variable Model

struct EnvVar: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

// MARK: - Service Form Content

struct ServiceFormContent: View {
    @Binding var draft: ServiceDraft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Basic Info
                FormSection(title: "Basic Info") {
                    FormField(label: "Name") {
                        TextField("My Service", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    Picker("Type", selection: $draft.isScript) {
                        Text("Command").tag(false)
                        Text("Script (start / stop / status)").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if draft.isScript {
                        FormField(label: "Script") {
                            HStack(spacing: 8) {
                                TextField("/path/to/service.sh", text: $draft.script.path)
                                    .textFieldStyle(.roundedBorder)
                                Button("Choose Script...") { chooseScript() }
                                    .buttonStyle(.bordered)
                            }
                        }
                        HStack(spacing: 12) {
                            FormField(label: "Start args") {
                                TextField("start", text: $draft.script.startArgs).textFieldStyle(.roundedBorder)
                            }
                            FormField(label: "Stop args") {
                                TextField("stop", text: $draft.script.stopArgs).textFieldStyle(.roundedBorder)
                            }
                            FormField(label: "Status args") {
                                TextField("status", text: $draft.script.statusArgs).textFieldStyle(.roundedBorder)
                            }
                        }
                    } else {
                        FormField(label: "Command", hint: "sudo works. DevDash shows a password popup.") {
                            TextField("/usr/bin/myservice start", text: $draft.command)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    FormField(label: "Working Directory") {
                        HStack(spacing: 8) {
                            TextField("/Users/me/project", text: $draft.workingDirectory)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                pick(directory: true, title: "Select Working Directory", start: draft.workingDirectory) {
                                    draft.workingDirectory = $0
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                // Tracking
                FormSection(title: "Tracking") {
                    if draft.isScript {
                        FormField(label: "Running when status output contains",
                                  hint: "Leave empty to use the status exit code (0 = running).") {
                            TextField("RUNNING", text: $draft.script.runningPattern)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        Picker("Track by", selection: $draft.tracking) {
                            ForEach(ServiceTracking.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        switch draft.tracking {
                        case .process:
                            Text("Running while the process DevDash started is alive.")
                                .font(.caption).foregroundColor(.secondary)
                        case .port:
                            FormField(label: "Port", hint: "Running while something listens on this port. Also finds it after a restart.") {
                                TextField("8080", text: $draft.port)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 120)
                            }
                        case .check:
                            FormField(label: "Check Command", hint: "Exit code 0 = running.") {
                                TextField("pgrep -f myservice", text: $draft.checkCommand)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    FormField(label: "Log File", hint: "Optional. Shown in the logs while the service runs. For services that write to a file.") {
                        HStack(spacing: 8) {
                            TextField("/path/to/service.log", text: $draft.logFile)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                pick(directory: false, title: "Select Log File", start: draft.logFile) { draft.logFile = $0 }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                // Environment Variables
                FormSection(title: "Environment Variables") {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("System environment variables are automatically available. Add variables here to override or extend them.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 4)

                    ForEach($draft.envVars) { $envVar in
                        HStack(spacing: 8) {
                            TextField("KEY", text: $envVar.key)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 160)
                            TextField("value", text: $envVar.value)
                                .textFieldStyle(.roundedBorder)
                            Button(action: { draft.envVars.removeAll { $0.id == envVar.id } }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button(action: { draft.envVars.append(EnvVar(key: "", value: "")) }) {
                        Label("Add Variable", systemImage: "plus.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                // Prerequisites
                FormSection(title: "Prerequisites") {
                    ForEach($draft.prerequisites) { $prereq in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                TextField("Command", text: $prereq.command)
                                    .textFieldStyle(.roundedBorder)
                                Button(action: { draft.prerequisites.removeAll { $0.id == prereq.id } }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            HStack(spacing: 16) {
                                HStack(spacing: 6) {
                                    Text("Delay (s)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("0", value: $prereq.delay, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 56)
                                }
                                Toggle("Required", isOn: $prereq.isRequired)
                                    .toggleStyle(.checkbox)
                                    .font(.callout)
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                    }
                    Button(action: { draft.prerequisites.append(PrerequisiteCommand(command: "", delay: 0, isRequired: false)) }) {
                        Label("Add Prerequisite", systemImage: "plus.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                // Advanced Commands
                FormSection(title: "Advanced Commands") {
                    if !draft.isScript {
                        FormField(label: "Stop Command", hint: "Defaults to SIGTERM → SIGKILL or port-based kill") {
                            TextField("myservice stop", text: $draft.stopCommand)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    FormField(label: "Restart Command", hint: "Defaults to stop + start") {
                        TextField("myservice restart", text: $draft.restartCommand)
                            .textFieldStyle(.roundedBorder)
                    }
                    FormField(label: "Max Log Lines", hint: "Default 1000. Leave empty for unlimited.") {
                        TextField("1000", text: $draft.maxLogLines)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                    }
                }
            }
            .padding(20)
        }
    }

    /// Pick a script and fill name, folder and (for svc-lib scripts) the log file
    private func chooseScript() {
        pick(directory: false, title: "Select Script", start: draft.script.path) { path in
            let found = ScriptConfig.detect(path: path)
            draft.script = found.script
            draft.workingDirectory = (path as NSString).deletingLastPathComponent
            if draft.name.isEmpty {
                draft.name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            }
            if let log = found.logFile { draft.logFile = log }
        }
    }

    private func pick(directory: Bool, title: String, start: String, onPick: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = !directory
        panel.canChooseDirectories = directory
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = directory
        let startPath = start.isEmpty ? NSHomeDirectory() : (directory ? start : (start as NSString).deletingLastPathComponent)
        panel.directoryURL = URL(fileURLWithPath: startPath)
        panel.begin { response in
            if response == .OK, let url = panel.url { onPick(url.path) }
        }
    }
}

// MARK: - Form Helpers

struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Divider()
            content()
        }
    }
}

struct FormField<Content: View>: View {
    let label: String
    var hint: String? = nil
    var width: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
            content()
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: width ?? .infinity, alignment: .leading)
    }
}
