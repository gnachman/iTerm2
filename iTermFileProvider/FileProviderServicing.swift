//
//  FileProviderServicing.swift
//  iTermFileProvider
//
//  Created by George Nachman on 6/11/22.
//

import Foundation
import FileProvider

extension FileProviderExtension: NSFileProviderServicing {
    public func supportedServiceSources(for itemIdentifier: NSFileProviderItemIdentifier,
                                        completionHandler: @escaping ([NSFileProviderServiceSource]?, Error?) -> Void) -> Progress {
        logger.debug("Extension: supportedServiceSources(for: \(itemIdentifier.rawValue, privacy: .public)")
        completionHandler([service], nil)
        let progress = Progress()
        progress.cancellationHandler = { completionHandler(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) }
        return progress
    }
}
