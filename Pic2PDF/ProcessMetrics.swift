//
//  ProcessMetrics.swift
//  Pic2PDF
//
//  Created by AI Assistant on 2025-01-30.
//
//
import Foundation
import UIKit
import MachO

class ProcessMetrics {
    /// Returns the current resident memory usage in MB
    static func currentResidentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024 * 1024) // Convert to MB
        } else {
            return 0.0
        }
    }
    
    private static var previousCpuInfo = host_cpu_load_info()
    private static var hasCpuBaseline = false
    
    /// Returns system-wide CPU usage (0-100%)
    static func currentCPUUsage() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var cpuInfo = host_cpu_load_info()
        
        let result = withUnsafeMutablePointer(to: &cpuInfo) { infoPtr -> kern_return_t in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPtr, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        defer {
            previousCpuInfo = cpuInfo
            hasCpuBaseline = true
        }
        
        guard hasCpuBaseline else {
            return 0
        }
        
        let user = Double(cpuInfo.cpu_ticks.0 - previousCpuInfo.cpu_ticks.0)
        let system = Double(cpuInfo.cpu_ticks.1 - previousCpuInfo.cpu_ticks.1)
        let idle = Double(cpuInfo.cpu_ticks.2 - previousCpuInfo.cpu_ticks.2)
        let nice = Double(cpuInfo.cpu_ticks.3 - previousCpuInfo.cpu_ticks.3)
        
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        
        let busy = user + system + nice
        let usage = (busy / total) * 100.0
        return min(max(usage, 0), 100)
    }

    /// Returns system uptime in seconds
    static func systemUptime() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }

    /// Returns device thermal state description
    static func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

