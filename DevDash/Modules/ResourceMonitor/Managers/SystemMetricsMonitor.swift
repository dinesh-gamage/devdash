//
//  SystemMetricsMonitor.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-23.
//

import Foundation
import Combine

// MARK: - System Metrics Monitor

@MainActor
class SystemMetricsMonitor: ObservableObject {
    @Published var currentMetrics: SystemMetrics?

    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 3.0  // 3 seconds (reduced frequency)
    private var previousCPUInfo: host_cpu_load_info?

    // Minimum change threshold to trigger UI update (reduce unnecessary publishes)
    private let changeThreshold: Double = 2.0  // 2% minimum change (increased threshold)

    init() {
        // Don't start monitoring automatically - wait for view to appear
    }

    nonisolated deinit {
        Task { @MainActor in
            self.updateTimer?.invalidate()
        }
    }

    // MARK: - Monitoring Control

    func startMonitoring() {
        // Initial update
        updateMetrics()

        // Schedule periodic updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMetrics()
            }
        }
    }

    func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Metrics Collection

    private func updateMetrics() {
        guard let memory = getMemoryUsage(),
              let cpu = getCPUUsage() else {
            return
        }

        let newMetrics = SystemMetrics(
            cpuUsagePercent: cpu,
            memoryUsedGB: memory.used,
            memoryTotalGB: memory.total
        )

        // Only publish if significant change
        if shouldPublish(newMetrics) {
            currentMetrics = newMetrics
        }
    }

    private func shouldPublish(_ newMetrics: SystemMetrics) -> Bool {
        guard let current = currentMetrics else { return true }

        let cpuDelta = abs(newMetrics.cpuUsagePercent - current.cpuUsagePercent)
        let memoryDelta = abs(newMetrics.memoryUsagePercent - current.memoryUsagePercent)

        return cpuDelta >= changeThreshold || memoryDelta >= changeThreshold
    }

    // MARK: - Memory Usage (via host_statistics64)

    private func getMemoryUsage() -> (used: Double, total: Double)? {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        // Get physical memory
        var physicalMemory: UInt64 = 0
        var physicalMemorySize = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &physicalMemory, &physicalMemorySize, nil, 0)

        let pageSize = vm_kernel_page_size
        let totalGB = Double(physicalMemory) / 1_073_741_824.0  // Convert to GB

        // Calculate used memory
        let activePages = UInt64(stats.active_count)
        let inactivePages = UInt64(stats.inactive_count)
        let wiredPages = UInt64(stats.wire_count)
        let compressedPages = UInt64(stats.compressor_page_count)

        let usedPages = activePages + inactivePages + wiredPages + compressedPages
        let usedBytes = usedPages * UInt64(pageSize)
        let usedGB = Double(usedBytes) / 1_073_741_824.0

        return (used: usedGB, total: totalGB)
    }

    // MARK: - CPU Usage (via host_processor_info)

    private func getCPUUsage() -> Double? {
        var processorCount: mach_msg_type_number_t = 0
        var cpuInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &infoCount
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else {
            return nil
        }

        defer {
            // Clean up allocated memory
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        // Calculate CPU usage
        var totalUser: UInt32 = 0
        var totalSystem: UInt32 = 0
        var totalIdle: UInt32 = 0
        var totalNice: UInt32 = 0

        for i in 0..<Int(processorCount) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += UInt32(info[offset + Int(CPU_STATE_USER)])
            totalSystem += UInt32(info[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle += UInt32(info[offset + Int(CPU_STATE_IDLE)])
            totalNice += UInt32(info[offset + Int(CPU_STATE_NICE)])
        }

        let currentInfo = host_cpu_load_info(
            cpu_ticks: (
                totalUser,
                totalSystem,
                totalIdle,
                totalNice
            )
        )

        // Calculate delta if we have previous data
        guard let previous = previousCPUInfo else {
            previousCPUInfo = currentInfo
            return 0.0  // First run, no delta yet
        }

        let userDelta = currentInfo.cpu_ticks.0 - previous.cpu_ticks.0
        let systemDelta = currentInfo.cpu_ticks.1 - previous.cpu_ticks.1
        let idleDelta = currentInfo.cpu_ticks.2 - previous.cpu_ticks.2
        let niceDelta = currentInfo.cpu_ticks.3 - previous.cpu_ticks.3

        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta

        guard totalDelta > 0 else {
            return 0.0
        }

        let usedDelta = userDelta + systemDelta + niceDelta
        let cpuPercent = (Double(usedDelta) / Double(totalDelta)) * 100.0

        previousCPUInfo = currentInfo

        return cpuPercent
    }
}
