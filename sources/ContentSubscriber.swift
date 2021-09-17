//
//  ContentSubscriber.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/1/21.
//

import Foundation

@objc(iTermContentSubscriber)
protocol ContentSubscriber {
    @objc func deliver(_ array: ScreenCharArray, metadata: iTermMetadata)
}
