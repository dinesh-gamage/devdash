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
    private let updateInterval: TimeInterval = 1.0  // 1 second
    private var previousCPUInfo: host_cpu_load_info?

    // Minimum change threshold to trigger UI update (reduce unnecessary publishes)
    private let changeThreshold: Double = 2.0  // 2% minimum change

    // Per-process CPU tracking cache
    private var processCPUCache: [pid_t: (timestamp: TimeInterval, cpuTime: UInt64)] = [:]

    // Cached DevDash aggregated metrics
    private var cachedDevDashMetrics: (metrics: (totalCPU: Double, totalMemoryMB: Double, processCount: Int), timestamp: TimeInterval)?
    private let devDashMetricsCacheDuration: TimeInterval = 1.0  // Cache for 1 second

    init() {
        // Pre-warm CPU cache for accurate first measurement
        // This prevents all widgets from showing 0% on first load
        prewarmCPUCache()
    }

    /// Pre-populate CPU cache with baseline measurements for common processes
    private func prewarmCPUCache() {
        // First pass: Establish baseline
        let devdashPID = ProcessInfo.processInfo.processIdentifier
        _ = getProcessCPU(pid: devdashPID)

        let maxProcs = 1024
        var pids = [pid_t](repeating: 0, count: maxProcs)
        let procCount = proc_listallpids(&pids, Int32(maxProcs * MemoryLayout<pid_t>.size))

        for i in 0..<min(50, Int(procCount)) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            _ = getProcessCPU(pid: pid)
        }

        // Second pass after small delay: Get actual CPU readings
        // This ensures first widget fetch has real data
        Thread.sleep(forTimeInterval: 0.1)  // 100ms delay

        _ = getProcessCPU(pid: devdashPID)
        for i in 0..<min(50, Int(procCount)) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            _ = getProcessCPU(pid: pid)
        }
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

        // Swap is optional - fallback to zeros if unavailable
        let swap = getSwapUsage() ?? (used: 0.0, total: 0.0)

        // Network and disk (optional - fallback to zeros for now)
        let network = getNetworkUsage() ?? (download: 0.0, upload: 0.0)
        let disk = getDiskUsage() ?? (read: 0.0, write: 0.0)

        let newMetrics = SystemMetrics(
            cpuUsagePercent: cpu,
            memoryUsedGB: memory.used,
            memoryTotalGB: memory.total,
            swapUsedGB: swap.used,
            swapTotalGB: swap.total,
            networkDownloadMBps: network.download,
            networkUploadMBps: network.upload,
            diskReadMBps: disk.read,
            diskWriteMBps: disk.write
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
        let swapDelta = abs(newMetrics.swapUsagePercent - current.swapUsagePercent)

        return cpuDelta >= changeThreshold || memoryDelta >= changeThreshold || swapDelta >= changeThreshold
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

        // Calculate used memory (App Memory in Activity Monitor)
        // Formula: Active + Wired + Compressed
        // Inactive pages are cached/reclaimable and excluded from "used"
        let activePages = UInt64(stats.active_count)
        let wiredPages = UInt64(stats.wire_count)
        let compressorPages = UInt64(stats.compressor_page_count)  // Physical memory occupied by compressor

        let usedPages = activePages + wiredPages + compressorPages
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

    // MARK: - Swap Usage (via sysctl vm.swapusage)

    private func getSwapUsage() -> (used: Double, total: Double)? {
        // Define xsw_usage struct matching C struct from sys/sysctl.h
        var swapUsage = xsw_usage(xsu_total: 0, xsu_avail: 0, xsu_used: 0, xsu_pagesize: 0, xsu_encrypted: 0)
        var size = MemoryLayout<xsw_usage>.size

        let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)

        guard result == 0 else { return nil }

        let usedGB = Double(swapUsage.xsu_used) / 1_073_741_824.0  // Convert to GB
        let totalGB = Double(swapUsage.xsu_total) / 1_073_741_824.0

        return (used: usedGB, total: totalGB)
    }

    // MARK: - Network Usage (via sysctl NET_RT_IFLIST2)

    private func getNetworkUsage() -> (download: Double, upload: Double)? {
        // TODO: Implement network monitoring with NET_RT_IFLIST2
        // For now, return zeros to unblock widget loading
        return (download: 0.0, upload: 0.0)
    }

    // MARK: - Disk I/O (via IOKit)

    private func getDiskUsage() -> (read: Double, write: Double)? {
        // TODO: Implement disk I/O monitoring with IOKit
        // For now, return zeros to unblock widget loading
        return (read: 0.0, write: 0.0)
    }

    // MARK: - Top Processes

    func getTopProcesses(sortBy: ProcessSortOption, limit: Int = 10) -> [SystemProcess] {
        // Get list of all process IDs
        let maxProcs = 1024
        var pids = [pid_t](repeating: 0, count: maxProcs)
        let procCount = proc_listallpids(&pids, Int32(maxProcs * MemoryLayout<pid_t>.size))

        guard procCount > 0 else { return [] }

        // Use min-heap to maintain top N processes (more efficient than sorting full array)
        var topProcesses: [SystemProcess] = []
        topProcesses.reserveCapacity(limit)

        // Iterate through PIDs and maintain top N
        for i in 0..<Int(procCount) {
            let pid = pids[i]
            guard pid > 0 else { continue }

            // Fetch only the info needed for the selected sort metric
            guard let processInfo = getProcessInfo(pid: pid, sortBy: sortBy) else { continue }

            // Add to top N list
            if topProcesses.count < limit {
                topProcesses.append(processInfo)
                if topProcesses.count == limit {
                    // Sort once when we reach limit size
                    topProcesses.sort { compareProcesses($0, $1, by: sortBy) }
                }
            } else {
                // Check if current process beats the worst in top N
                let worstInTop = topProcesses.last!
                if compareProcesses(processInfo, worstInTop, by: sortBy) {
                    // Replace worst and re-sort
                    topProcesses[limit - 1] = processInfo
                    topProcesses.sort { compareProcesses($0, $1, by: sortBy) }
                }
            }
        }

        return topProcesses
    }

    // Compare two processes based on sort option (returns true if p1 > p2)
    private func compareProcesses(_ p1: SystemProcess, _ p2: SystemProcess, by sortBy: ProcessSortOption) -> Bool {
        switch sortBy {
        case .cpu:
            return p1.cpuPercent > p2.cpuPercent
        case .memory:
            return p1.memoryMB > p2.memoryMB
        case .network:
            return p1.networkMBps > p2.networkMBps
        case .disk:
            return p1.diskMBps > p2.diskMBps
        }
    }

    private func getProcessInfo(pid: pid_t, sortBy: ProcessSortOption) -> SystemProcess? {
        // Get process name (always needed)
        let maxPathSize = 4096
        var pathBuffer = [CChar](repeating: 0, count: maxPathSize)
        let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(maxPathSize))

        let name: String
        if pathLen > 0 {
            let fullPath = String(cString: pathBuffer)
            name = URL(fileURLWithPath: fullPath).lastPathComponent
        } else {
            name = "Unknown"
        }

        // Fetch metrics based on sort option (optimization: only fetch what's needed)
        var cpuPercent: Double = 0.0
        var memoryMB: Double = 0.0
        var networkMBps: Double = 0.0
        var diskMBps: Double = 0.0

        switch sortBy {
        case .memory:
            memoryMB = getProcessMemory(pid: pid)
        case .cpu:
            cpuPercent = getProcessCPU(pid: pid)
        case .network:
            networkMBps = 0.0  // TODO: Implement network tracking
        case .disk:
            diskMBps = 0.0      // TODO: Implement disk I/O tracking
        }

        return SystemProcess(
            id: pid,
            name: name,
            cpuPercent: cpuPercent,
            memoryMB: memoryMB,
            networkMBps: networkMBps,
            diskMBps: diskMBps
        )
    }

    private func getProcessMemory(pid: pid_t) -> Double {
        var taskInfo = proc_taskinfo()
        let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))

        guard size > 0 else { return 0.0 }

        // Return resident memory in MB
        return Double(taskInfo.pti_resident_size) / 1_048_576.0
    }

    private func getProcessCPU(pid: pid_t) -> Double {
        var taskInfo = proc_taskinfo()
        let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))

        guard size > 0 else { return 0.0 }

        // Total CPU time in nanoseconds (user + system)
        let currentCPUTime = taskInfo.pti_total_user + taskInfo.pti_total_system
        let currentTimestamp = Date().timeIntervalSince1970

        // Check if we have previous measurement for this process
        if let cached = processCPUCache[pid] {
            // Calculate delta
            let timeDelta = currentTimestamp - cached.timestamp
            let cpuDelta = currentCPUTime - cached.cpuTime

            // Update cache
            processCPUCache[pid] = (timestamp: currentTimestamp, cpuTime: currentCPUTime)

            guard timeDelta > 0 else { return 0.0 }

            // Convert CPU delta from nanoseconds to seconds
            let cpuDeltaSeconds = Double(cpuDelta) / 1_000_000_000.0

            // CPU percentage = (CPU time used / wall time elapsed) * 100
            let cpuPercent = (cpuDeltaSeconds / timeDelta) * 100.0

            return min(cpuPercent, 100.0)
        } else {
            // First measurement - store and return 0
            processCPUCache[pid] = (timestamp: currentTimestamp, cpuTime: currentCPUTime)
            return 0.0
        }
    }

    // MARK: - DevDash-Specific Monitoring

    func getDevDashProcesses(sortBy: ProcessSortOption) -> [SystemProcess] {
        let devdashPID = ProcessInfo.processInfo.processIdentifier
        var devdashProcesses: [SystemProcess] = []

        // Get DevDash main process
        if let mainProcess = getProcessInfo(pid: devdashPID, sortBy: sortBy) {
            devdashProcesses.append(mainProcess)
        }

        // Get all child processes
        let maxProcs = 1024
        var childPIDs = [pid_t](repeating: 0, count: maxProcs)
        let childCount = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(devdashPID), &childPIDs, Int32(maxProcs * MemoryLayout<pid_t>.size))

        guard childCount > 0 else {
            // No children, just return main process
            return devdashProcesses
        }

        // Add all child processes
        for i in 0..<Int(childCount) {
            let pid = childPIDs[i]
            guard pid > 0 else { continue }

            if let childProcess = getProcessInfo(pid: pid, sortBy: sortBy) {
                devdashProcesses.append(childProcess)
            }
        }

        // Sort by selected metric
        devdashProcesses.sort { compareProcesses($0, $1, by: sortBy) }

        return devdashProcesses
    }

    func getDevDashAggregatedMetrics() -> (totalCPU: Double, totalMemoryMB: Double, processCount: Int) {
        let currentTime = Date().timeIntervalSince1970

        // Return cached result if still valid
        if let cached = cachedDevDashMetrics,
           currentTime - cached.timestamp < devDashMetricsCacheDuration {
            return cached.metrics
        }

        // Calculate fresh metrics
        let devdashPID = ProcessInfo.processInfo.processIdentifier
        var totalCPU: Double = 0.0
        var totalMemory: Double = 0.0
        var count = 0

        // Get DevDash main process metrics
        let mainMemory = getProcessMemory(pid: devdashPID)
        let mainCPU = getProcessCPU(pid: devdashPID)
        totalMemory += mainMemory
        totalCPU += mainCPU
        count += 1

        // Get all child processes
        let maxProcs = 1024
        var childPIDs = [pid_t](repeating: 0, count: maxProcs)
        let childCount = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(devdashPID), &childPIDs, Int32(maxProcs * MemoryLayout<pid_t>.size))

        if childCount > 0 {
            for i in 0..<Int(childCount) {
                let pid = childPIDs[i]
                guard pid > 0 else { continue }

                let memory = getProcessMemory(pid: pid)
                let cpu = getProcessCPU(pid: pid)
                totalMemory += memory
                totalCPU += cpu
                count += 1
            }
        }

        let result = (totalCPU: totalCPU, totalMemoryMB: totalMemory, processCount: count)

        // Cache the result
        cachedDevDashMetrics = (metrics: result, timestamp: currentTime)

        return result
    }
}

// MARK: - xsw_usage Struct

/// Swap usage structure (from sys/sysctl.h)
/// Note: boolean_t in C is UInt32, not Bool
private struct xsw_usage {
    var xsu_total: UInt64
    var xsu_avail: UInt64
    var xsu_used: UInt64
    var xsu_pagesize: UInt32
    var xsu_encrypted: UInt32  // boolean_t = UInt32 in C
}
