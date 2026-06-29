//
//  ContentSubscriber.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/1/21.
//

import Foundation

@objc(iTermContentSubscriber)
protocol ContentSubscriber {
    @objc func deliver(_ array: ScreenCharArray, metadata: iTermImmutableMetadata, lineBufferGeneration: Int64)
    @objc func updateMetadata(selectedCommandRange: NSRange, cumulativeOverflow: Int64)
}
