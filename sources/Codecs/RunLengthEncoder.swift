//
//  RunLengthEncoder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/10/22.
//

import Foundation

// Group sequential elements of the same kind and pass them to the emitter.
class RunLengthEncoder<Element, Kind: Hashable> {
    private var buffer = [Element]()
    private var kind: Kind? = nil
    private let emitter: (([Element], Kind) -> Void)
    private let maxLengths: [Kind: Int]
    private let classifier: (Element) -> Kind

    // If a particluar Kind has a max length defined the emitter will never get more than that
    // many elements in one call. Otherwise the max is unbounded.
    // The emitter is guranteed to be called with every element exactly once in the order it was added.
    // The classifier's job is to assign a Kind to an Element.
    // Remember to call halt() when you're done.
    init(maxLengths: [Kind: Int],
         emitter: @escaping ([Element], Kind) -> Void,
         classifier:  @escaping (Element) -> Kind) {
        self.maxLengths = maxLengths
        self.emitter = emitter
        self.classifier = classifier
    }

    func append(_ element: Element) {
        append(element: element, kind: classifier(element))
    }

    private func append(element: Element, kind: Kind) {
        if kind != self.kind && self.kind != nil {
            flush()
        }
        self.kind = kind
        buffer.append(element)
        if let maxLength = maxLengths[kind], buffer.count == maxLength {
            flush()
        }
    }

    func halt() {
        if !buffer.isEmpty {
            flush()
        }
        self.kind = nil
    }

    func append<T: Sequence>(sequence: T) where T.Element == Element {
        sequence.forEach { value in
            append(element: value, kind: classifier(value))
        }
    }

    static func encode<T: Sequence>(sequence: T,
                                    maxLengths: [Kind: Int],
                                    emitter: @escaping ([Element], Kind) -> Void,
                                    classifier:  @escaping (Element) -> Kind) where T.Element == Element {
        let rle = RunLengthEncoder(maxLengths: maxLengths, emitter: emitter, classifier: classifier)
        rle.append(sequence: sequence)
        rle.halt()
    }

    private func flush() {
        precondition(!buffer.isEmpty)
        precondition(kind != nil)

        emitter(buffer, kind!)
        buffer = []
        kind = nil
    }
}

// Obj-C shim. Only supports NSNumber. Delete this when it is no longer needed.
@objc(iTermRunLengthEncoder)
class ObjCRunLengthEncoder: NSObject {
    @objc(encodeArray:maxLengths:emitter:classifier:)
    static func encode(array: [NSNumber],
                       maxLengths: [NSNumber: Int],
                       emitter: @escaping ([NSNumber], NSNumber) -> Void,
                       classifier:  @escaping (NSNumber) -> NSNumber) {
        RunLengthEncoder.encode(sequence: array,
                                maxLengths: maxLengths,
                                emitter: emitter,
                                classifier: classifier)
    }
}
