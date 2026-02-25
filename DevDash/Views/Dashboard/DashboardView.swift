//
//  DashboardView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

struct DashboardView: View {
    let onSelectModule: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                DashboardHeader()

                // Dashboard Grid
                DashboardGrid(totalColumns: 12, spacing: 16) {
                    // Row 1: Count Widgets (6 items @ 2 columns each)
                    DashboardGridRow {
                        DashboardGridItem(columnSpan: 2, minHeight: 85) {
                            ServiceCountWidget(onTap: {
                                onSelectModule("service-manager")
                            })
                        }

                        DashboardGridItem(columnSpan: 2, minHeight: 85) {
                            EC2CountWidget(onTap: {
                                onSelectModule("ec2-manager")
                            })
                        }

                        DashboardGridItem(columnSpan: 2, minHeight: 85) {
                            CredentialsCountWidget(onTap: {
                                onSelectModule("credentials-manager")
                            })
                        }

                        DashboardGridItem(columnSpan: 2, minHeight: 85) {
                            AWSVaultCountWidget(onTap: {
                                onSelectModule("aws-vault-manager")
                            })
                        }

                        DashboardGridItem(columnSpan: 2, minHeight: 85) {
                            DevDashCPUCountWidget(onTap: {
                                ResourceMonitorState.shared.selectedView = .devdash
                                onSelectModule("resource-monitor")
                            })
                        }

                        DashboardGridItem(columnSpan: 2, minHeight: 85) {
                            DevDashMemoryCountWidget(onTap: {
                                ResourceMonitorState.shared.selectedView = .devdash
                                onSelectModule("resource-monitor")
                            })
                        }
                    }

                    // Row 2: Dashboard Widgets (3 items @ 4 columns each)
                    DashboardGridRow {
                        DashboardGridItem(columnSpan: 4, minHeight: 350) {
                            ServiceDashboardWidget(
                                onModuleTap: { onSelectModule("service-manager") }
                            )
                        }

                        DashboardGridItem(columnSpan: 4, minHeight: 350) {
                            EC2DashboardWidget(
                                onModuleTap: { onSelectModule("ec2-manager") }
                            )
                        }

                        DashboardGridItem(columnSpan: 4, minHeight: 350) {
                            ResourceMonitorWidget(
                                isDashboard: true,
                                onModuleTap: {
                                    ResourceMonitorState.shared.selectedView = .overall
                                    onSelectModule("resource-monitor")
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Dashboard Header

struct DashboardHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("DevDashLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)

            Text("Welcome back, \(NSFullUserName())")
                .font(.title3)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}
