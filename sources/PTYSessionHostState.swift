//
//  PTYSessionHostState.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/24.
//

import Foundation

@objc
class PTYSessionHostState: NSObject {
    @objc override var description: String {
        return "<\(NSStringFromClass(Self.self)): \(it_addressString) remoteHost=\(remoteHost?.description ?? "(nil)") keyMappingMode=\(keyMappingMode)>"
    }
    
    @objc var remoteHost: VT100RemoteHostReading?
    @objc var keyMappingMode: iTermKeyMappingMode = .standard
}
