//
//  ImagesListDetailView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

struct ImagesListDetailView: View {
    @ObservedObject var state = DockerManagerState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ModuleDetailHeader(
                title: "Images",
                actionButtons: {
                    VariantButton(icon: "arrow.clockwise", variant: .secondary, tooltip: "Refresh") {
                        Task {
                            await state.manager.refreshImagesList()
                        }
                    }
                }
            )

            Divider()

            // Images Table
            if state.manager.imagesList.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "cube")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Images")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("No Docker images found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(state.manager.imagesList) {
                    TableColumn("Repository") { image in
                        Text(image.repository)
                            .font(.body)
                    }
                    .width(min: 150, ideal: 200, max: 300)

                    TableColumn("Tag") { image in
                        Text(image.tag)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .width(min: 80, ideal: 100, max: 150)

                    TableColumn("Image ID") { image in
                        InlineCopyableText(image.imageId, monospaced: true)
                    }
                    .width(min: 150, ideal: 200, max: 250)

                    TableColumn("Size") { image in
                        Text(image.size)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .width(min: 80, ideal: 100, max: 120)

                    TableColumn("Actions") { image in
                        HStack(spacing: 6) {
                            VariantButton(icon: "trash", variant: .danger, tooltip: "Delete Image") {
                                state.imageToDelete = image
                                state.showingDeleteImageConfirmation = true
                            }
                        }
                    }
                    .width(min: 80, ideal: 80, max: 80)
                }
                .padding()
            }
        }
        .task {
            await state.manager.refreshImagesList()
        }
    }
}
