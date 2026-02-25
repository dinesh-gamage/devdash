//
//  DashboardGridItem.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

/// Represents an item in the dashboard grid with configurable column span and content
struct DashboardGridItem: Identifiable {
    let id = UUID()
    let columnSpan: Int  // How many columns to span (1-12)
    let minHeight: CGFloat?  // Optional minimum height
    let content: AnyView

    init(columnSpan: Int = 1, minHeight: CGFloat? = nil, @ViewBuilder content: () -> some View) {
        self.columnSpan = columnSpan
        self.minHeight = minHeight
        self.content = AnyView(content())
    }
}

/// Represents a row in the dashboard grid
struct DashboardGridRow: Identifiable {
    let id = UUID()
    let items: [DashboardGridItem]

    init(@DashboardGridRowBuilder items: () -> [DashboardGridItem]) {
        self.items = items()
    }
}

/// Result builder for creating grid rows declaratively
@resultBuilder
struct DashboardGridRowBuilder {
    static func buildBlock(_ items: DashboardGridItem...) -> [DashboardGridItem] {
        items
    }
}

/// Result builder for creating grid layout declaratively
@resultBuilder
struct DashboardGridBuilder {
    static func buildBlock(_ rows: DashboardGridRow...) -> [DashboardGridRow] {
        rows
    }
}
