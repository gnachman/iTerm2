//
//  FileProviderServicing.swift
//  iTermFileProvider
//
//  Created by George Nachman on 6/11/22.
//

import Foundation
import FileProvider
import FileProviderService

extension FileProviderExtension: NSFileProviderServicing {
    public func supportedServiceSources(for itemIdentifier: NSFileProviderItemIdentifier,
                                        completionHandler: @escaping ([NSFileProviderServiceSource]?, Error?) -> Void) -> Progress {
        FileProviderLogging.logger.debug("Extension: supportedServiceSources(for: \(itemIdentifier.rawValue)")
        completionHandler([xpcService], nil)
        let progress = Progress()
        progress.cancellationHandler = { completionHandler(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) }
        return progress
    }
}
