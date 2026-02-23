//
//  ServiceListItem.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct ServiceListItem: View {
    let serviceInfo: ServiceInfo
    let isSelected: Bool
    let manager: ServiceManager
    var onDelete: () -> Void
    var onEdit: () -> Void

    @State private var isHovering = false
    @State private var isStartHovering = false
    @State private var isStopHovering = false
    @State private var isRestartHovering = false
    @State private var isEditHovering = false
    @State private var isDeleteHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(serviceInfo.isRunning ? AppTheme.statusRunning : AppTheme.statusStopped)
                .frame(width: 8, height: 8)

            Text(serviceInfo.name)
                .font(AppTheme.h3)

            Spacer()

            HStack(spacing: AppTheme.actionButtonSpacing) {
                // Quick action buttons
                if serviceInfo.isRunning {
                    VariantButton(
                        icon: "stop.fill",
                        variant: .danger,
                        tooltip: "Stop",
                        isLoading: serviceInfo.processingAction == .stopping
                    ) {
                        manager.getRuntime(id: serviceInfo.id)?.stop()
                    }
                    .disabled(serviceInfo.processingAction != nil)

                    VariantButton(
                        icon: "arrow.clockwise",
                        variant: .primary,
                        tooltip: "Restart",
                        isLoading: serviceInfo.processingAction == .restarting
                    ) {
                        manager.getRuntime(id: serviceInfo.id)?.restart()
                    }
                    .disabled(serviceInfo.processingAction != nil)
                } else {
                    VariantButton(
                        icon: "play.fill",
                        variant: .primary,
                        tooltip: "Start",
                        isLoading: serviceInfo.processingAction == .starting
                    ) {
                        manager.getRuntime(id: serviceInfo.id)?.start()
                    }
                    .disabled(serviceInfo.processingAction != nil)
                }

                Divider()
                    .frame(height: 20)

                // Edit/Delete buttons
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: AppTheme.actionButtonSize))
                        .foregroundColor(.accentColor)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isEditHovering ? Color.accentColor.opacity(AppTheme.buttonHoverBackground) : AppTheme.clearColor)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isEditHovering = hovering
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: AppTheme.actionButtonSize))
                        .foregroundColor(AppTheme.errorColor)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isDeleteHovering ? AppTheme.errorColor.opacity(AppTheme.buttonHoverBackground) : AppTheme.clearColor)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isDeleteHovering = hovering
                }
            }
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .padding(.vertical, AppTheme.itemVerticalPadding)
        .padding(.horizontal, AppTheme.itemHorizontalPadding)
        .contentShape(Rectangle())
        .listRowBackground(
            RoundedRectangle(cornerRadius: AppTheme.itemCornerRadius)
                .fill((isSelected || isHovering) ? Color.accentColor.opacity(AppTheme.itemSelectedBackground) : AppTheme.clearColor)
        )
        // .listRowInsets(EdgeInsets())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
