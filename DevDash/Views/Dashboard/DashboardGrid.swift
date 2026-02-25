//
//  DashboardGrid.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-25.
//

import SwiftUI

/// A flexible grid system supporting masonry-style layouts with configurable column spans
struct DashboardGrid: View {
    let totalColumns: Int  // Total columns in the grid (default: 12)
    let spacing: CGFloat  // Spacing between items
    let rows: [DashboardGridRow]

    init(
        totalColumns: Int = 12,
        spacing: CGFloat = 16,
        @DashboardGridBuilder rows: () -> [DashboardGridRow]
    ) {
        self.totalColumns = totalColumns
        self.spacing = spacing
        self.rows = rows()
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows) { row in
                DashboardGridRowView(
                    row: row,
                    totalColumns: totalColumns,
                    spacing: spacing
                )
            }
        }
    }
}

/// Renders a single row of the dashboard grid
private struct DashboardGridRowView: View {
    let row: DashboardGridRow
    let totalColumns: Int
    let spacing: CGFloat

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: spacing) {
                ForEach(row.items) { item in
                    item.content
                        .frame(width: calculateWidth(
                            for: item.columnSpan,
                            totalWidth: geometry.size.width
                        ))
                        .frame(minHeight: item.minHeight)
                }
            }
        }
        .frame(height: calculateRowHeight())
    }

    /// Calculate width for an item based on its column span
    private func calculateWidth(for columnSpan: Int, totalWidth: CGFloat) -> CGFloat {
        // Total spacing = (number of items - 1) * spacing
        let totalSpacing = CGFloat(row.items.count - 1) * spacing

        // Available width after accounting for spacing
        let availableWidth = totalWidth - totalSpacing

        // Total columns used in this row
        let totalColumnsUsed = row.items.reduce(0) { $0 + $1.columnSpan }

        // Width per column
        let widthPerColumn = availableWidth / CGFloat(totalColumnsUsed)

        // Width for this item
        return widthPerColumn * CGFloat(columnSpan)
    }

    /// Calculate height for the row (uses the maximum minHeight if specified)
    private func calculateRowHeight() -> CGFloat? {
        let heights = row.items.compactMap { $0.minHeight }
        return heights.max()
    }
}
