//
//  EditServiceView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct EditServiceView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: ServiceManager
    let service: ServiceRuntime
    @State private var draft: ServiceDraft

    init(manager: ServiceManager, service: ServiceRuntime) {
        self.manager = manager
        self.service = service
        _draft = State(initialValue: ServiceDraft(service.config))
    }

    var body: some View {
        NavigationStack {
            ServiceFormContent(draft: $draft)
            .navigationTitle("Edit Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        manager.updateService(service, with: draft.config(id: service.config.id))
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 560)
    }
}
