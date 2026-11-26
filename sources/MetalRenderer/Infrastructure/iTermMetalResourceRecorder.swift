//
//  iTermMetalResourceRecorder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/25/26.
//

import Foundation
import Metal

// Collects the buffers and textures a frame binds so they can be referenced again later without
// rebuilding the frame.
//
// Why: after about a second with no GPU work that touches an allocation, macOS unwires it, and the
// next command buffer that uses it pays to wire it back in. That shows up as a long hitch on the
// first frame after a short period of inactivity. The metalRedrawPeriod timer used to work around
// this by drawing a full frame every half second, which costs a lot of CPU while idle. Instead,
// iTermMetalDriver can submit a command buffer that only declares use of the last frame's
// resources (see -keepResourcesWarm) for a tiny fraction of the cost.
@objc(iTermMetalResourceRecorder)
class iTermMetalResourceRecorder: NSObject {
    private let mutex = Mutex()
    private var resources = [ObjectIdentifier: MTLResource]()

    @objc(recordResource:)
    func record(_ resource: MTLResource) {
        mutex.sync {
            resources[ObjectIdentifier(resource)] = resource
        }
    }

    @objc(removeResource:)
    func remove(_ resource: MTLResource) {
        _ = mutex.sync {
            resources.removeValue(forKey: ObjectIdentifier(resource))
        }
    }

    @objc
    var allResources: [MTLResource] {
        mutex.sync {
            Array(resources.values)
        }
    }
}
