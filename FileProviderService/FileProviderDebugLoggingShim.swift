//
//  FileProviderDebugLoggingShim.swift
//  FileProviderService
//
//  Created by George Nachman on 9/30/22.
//

import Foundation

var gDebugLogging = ObjCBool(true)
func DebugLogImpl(_ file: String, _ line: Int32, _ function: String, _ message: String) {
    // Use iTermLogger instead. This only exists to make it compile in targets that don't
    // have debug logging.
}
