//
//  AddServiceView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct AddServiceView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var manager: ServiceManager
    @State private var draft = ServiceDraft()

    var body: some View {
        NavigationStack {
            ServiceFormContent(draft: $draft)
            .navigationTitle("Add Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        manager.addService(draft.config())
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 560)
    }
}
