//
//  ScanProgressView.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import SwiftUI

struct ScanProgressView: View {
    let message: String
    let currentPath: String?
    let locationInfos: [LocationScanInfo]

    var body: some View {
        // Compact location list
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(locationInfos) { locationInfo in
                    LocationScanRow(locationInfo: locationInfo)
                    Divider()
                }
            }
        }
    }
}

// MARK: - Location Scan Row (Compact)

struct LocationScanRow: View {
    let locationInfo: LocationScanInfo

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator (circle or spinner or checkmark)
            statusIndicator
                .frame(width: 20)

            // Location name and status message
            VStack(alignment: .leading, spacing: 4) {
                Text(locationInfo.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(textColor)

                // Status message below name
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.8))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(backgroundColor)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch locationInfo.status {
        case .pending:
            Circle()
                .fill(Color.gray)
                .frame(width: 8, height: 8)

        case .scanning:
            ProgressView()
                .scaleEffect(0.7)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.body)
        }
    }

    private var statusMessage: String {
        switch locationInfo.status {
        case .pending:
            return "Waiting..."

        case .scanning(let currentCategory):
            return "Scanning for \(currentCategory)..."

        case .completed(let filesFound, let sizeFound):
            if filesFound > 0 {
                let sizeStr = ByteCountFormatter.string(fromByteCount: sizeFound, countStyle: .file)
                return "\(filesFound) files found (\(sizeStr))"
            } else {
                return "No files found"
            }
        }
    }

    private var textColor: Color {
        switch locationInfo.status {
        case .pending:
            return .secondary
        case .scanning:
            return .blue
        case .completed:
            return .green
        }
    }

    private var backgroundColor: Color {
        switch locationInfo.status {
        case .pending:
            return Color.clear
        case .scanning:
            return Color.blue.opacity(0.05)
        case .completed:
            return Color.green.opacity(0.05)
        }
    }
}
