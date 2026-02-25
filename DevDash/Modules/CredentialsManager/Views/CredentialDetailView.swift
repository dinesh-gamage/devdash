//
//  CredentialDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-21.
//

import SwiftUI

struct CredentialDetailView: View {
    let credential: Credential

    @ObservedObject private var state = CredentialsManagerState.shared

    // Cache secrets to avoid repeated Keychain access on every view render
    @State private var cachedPassword: String?
    @State private var cachedAccessToken: String?
    @State private var cachedRecoveryCodes: String?
    @State private var cachedFieldValues: [UUID: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with metadata
                ModuleDetailHeader(
                    title: credential.title,
                    metadata: [
                        MetadataRow(icon: "folder.fill", label: "Category", value: credential.category),
                        MetadataRow(icon: "calendar", label: "Created", value: credential.createdAt.formatted(date: .abbreviated, time: .shortened)),
                        MetadataRow(icon: "clock", label: "Modified", value: credential.lastModified.formatted(date: .abbreviated, time: .shortened))
                    ],
                    actionButtons: {
                        HStack(spacing: 12) {
                            VariantButton("Edit", icon: "pencil", variant: .primary) {
                                state.credentialToEdit = credential
                                state.showingEditCredential = true
                            }
                        }
                    }
                )

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    // Username
                    if let username = credential.username {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Username", systemImage: "person.fill")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            HStack {
                                InlineCopyableText(username)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }

                    // URL/Server
                    if let url = credential.url {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("URL/Server", systemImage: "link")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            HStack {
                                InlineCopyableText(url)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    // Password
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Password", systemImage: "lock.fill")
                            .font(AppTheme.h3)
                            .foregroundColor(.secondary)

                        if let password = cachedPassword {
                            CopyableField(password, isSecret: true, monospaced: true)
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                        } else {
                            Text("Failed to load password")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.red)
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                        }
                    }

                    // Access Token
                    if let accessToken = cachedAccessToken {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Access Token", systemImage: "key.horizontal.fill")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            CopyableField(accessToken, isSecret: true, monospaced: true)
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                        }
                    }

                    // Recovery Codes
                    if let recoveryCodes = cachedRecoveryCodes {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Recovery Codes", systemImage: "shield.lefthalf.filled")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            CopyableField(recoveryCodes, isSecret: true, monospaced: true)
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                        }
                    }

                    // Additional Fields
                    if !credential.additionalFields.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Additional Fields", systemImage: "list.bullet")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            ForEach(credential.additionalFields) { field in
                                CredentialFieldRow(field: field, cachedValue: cachedFieldValues[field.id])
                            }
                        }
                    }

                    // Notes
                    if let notes = credential.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Notes", systemImage: "note.text")
                                .font(AppTheme.h3)
                                .foregroundColor(.secondary)

                            Text(notes)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            loadCredentialSecrets()
        }
        .onChange(of: credential.id) { _ in
            loadCredentialSecrets()
        }
    }

    private func loadCredentialSecrets() {
        // Load all secrets once when view appears
        cachedPassword = state.manager.getPasswordSafe(for: credential)
        cachedAccessToken = state.manager.getAccessTokenSafe(for: credential)
        cachedRecoveryCodes = state.manager.getRecoveryCodesSafe(for: credential)

        // Load additional field values
        cachedFieldValues.removeAll()
        for field in credential.additionalFields {
            if let value = state.manager.getFieldValueSafe(for: field) {
                cachedFieldValues[field.id] = value
            }
        }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case CredentialCategory.databases: return "cylinder.fill"
        case CredentialCategory.apiKeys: return "network"
        case CredentialCategory.ssh: return "terminal.fill"
        case CredentialCategory.websites: return "globe"
        case CredentialCategory.servers: return "server.rack"
        case CredentialCategory.applications: return "app.fill"
        default: return "key.fill"
        }
    }
}

// MARK: - Credential Field Row

struct CredentialFieldRow: View {
    let field: CredentialField
    let cachedValue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(field.key, systemImage: field.isSecret ? "lock.fill" : "text.alignleft")
                .font(AppTheme.h3)
                .foregroundColor(.secondary)

            if let value = cachedValue {
                CopyableField(value, isSecret: field.isSecret, monospaced: field.isSecret)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }
        }
    }
}
