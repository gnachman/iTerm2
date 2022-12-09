//
//  iTerm2SandboxedWorkerShims.swift
//  iTerm2SandboxedWorker
//
//  Created by George Nachman on 12/9/22.
//

import Foundation

@objc(FileProviderLogging) class FileProviderLogging: NSObject {
    @objc static var callback: ((String) -> ())? = nil
}

