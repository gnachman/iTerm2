//
//  iTermEnergyTests.swift
//  ModernTests
//
//  Tests for energy efficiency and resource leak fixes.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - Mach Port Leak Tests

class iTermMachPortLeakTests: XCTestCase {

    private func machPortCount() -> Int {
        var names: mach_port_name_array_t?
        var nameCount: mach_msg_type_number_t = 0
        var types: mach_port_type_array_t?
        var typeCount: mach_msg_type_number_t = 0

        let kr = mach_port_names(mach_task_self_, &names, &nameCount, &types, &typeCount)
        if kr == KERN_SUCCESS {
            if let names {
                vm_deallocate(mach_task_self_,
                              vm_address_t(bitPattern: names),
                              vm_size_t(nameCount) * vm_size_t(MemoryLayout<mach_port_name_t>.size))
            }
            if let types {
                vm_deallocate(mach_task_self_,
                              vm_address_t(bitPattern: types),
                              vm_size_t(typeCount) * vm_size_t(MemoryLayout<mach_port_type_t>.size))
            }
        }
        return Int(nameCount)
    }

    func testMachHostSelfWithDeallocateDoesNotLeakPorts() {
        // Verify that calling mach_host_self + mach_port_deallocate
        // does not leak ports. This is the pattern used in our fix for
        // iTermCPUUtilization and iTermMemoryUtilization.
        let portsBefore = machPortCount()

        for _ in 0..<500 {
            let host = mach_host_self()
            mach_port_deallocate(mach_task_self_, host)
        }

        let portsAfter = machPortCount()
        // Should not grow significantly (allow a few for system activity)
        XCTAssertLessThan(portsAfter, portsBefore + 10,
                          "Mach port count grew from \(portsBefore) to \(portsAfter) after 500 cycles with dealloc")
    }
}

// MARK: - CPU Utilization Tests

class iTermCPUUtilizationTests: XCTestCase {

    func testCPUUtilizationPublisherReportsValues() {
        // Verify that the CPU utilization publisher works correctly
        // after adding timer tolerance and fixing mach port leak.
        let publisher = iTermLocalCPUUtilizationPublisher.sharedInstance()
        let expectation = XCTestExpectation(description: "CPU value received")

        publisher.addSubscriber(self) { (payload: Any) in
            if let number = payload as? NSNumber, number.doubleValue >= 0 {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 3.0)
        publisher.removeSubscriber(self)
    }
}
