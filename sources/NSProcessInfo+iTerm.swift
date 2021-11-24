//
//  NSProcessInfo+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/24/21.
//

import Foundation

extension ProcessInfo {
    static var it_machine: String? {
        var sysinfo = utsname()
        guard uname(&sysinfo) == EXIT_SUCCESS else {
            return nil
        }
        let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
        guard let machine = String(bytes: data, encoding: .ascii) else {
            return nil
        }
        return machine.trimmingCharacters(in: .controlCharacters)
    }

    @objc static var it_hasARMProcessor: Bool {
        return (it_machine ?? "").contains("arm")
    }
}
