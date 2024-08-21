//
//  KittyImageCommand.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/24.
//

import Foundation

fileprivate func extractEnum<T: RawRepresentable>(from dict: [String: String],
                                                  key: String,
                                                  defaultValue: T) -> T? where T.RawValue == String {
    switch dict[key] {
    case .none:
        return defaultValue
    case .some(let value):
        return T(rawValue: value) ?? nil
    }
}

@objc(iTermKittyImageCommand)
class KittyImageCommand: NSObject {
    enum Action: String {
        case animationFrame = "f"  // transmit data for animation frames
        case query = "q"  // query terminal
        case transmit = "t"  // transmit data
        case transmitAndDisplay = "T"  // transmit data and display image
        case put = "p"  // put (display) previous transmitted image
        case delete = "d"  // delete image
        case controlAnimation = "a"  // control animation
        case compose = "c"  // compose animation frames
    }
    var action: Action  // a
    var payload: String

    struct ImageTransmission {
        enum Format: String {
            case raw24 = "24"
            case raw32 = "32"
            case png = "100"
        }
        enum Medium: String {
            case direct = "d"
            case file = "f"
            case temporaryFile = "t"
            case sharedMemory = "s"
        }
        enum Compression: String {
            case zlib = "z"
            case uncompressed = ""
        }
        enum More: String {
            case expectMore = "1"
            case finalChunk = "0"
        }
        enum Verbosity: String {
            case normal = "0"  // the documented behavior I guess?
            case query = "1"  // suppress success response
            case quiet = "2"  // supress error response
        }
        var format: Format  // f
        var medium: Medium  // t
        var width: UInt  // s
        var height: UInt  // v
        var size: UInt  // S
        var offset: UInt  // O
        var identifier: UInt32  // i
        var imageNumber: UInt32 // I
        var placement: UInt32  // p
        var compression: Compression  // o
        var more: More  // m
        var verbosity: Verbosity  // q
        var allocationAllowed = true

        init?(_ dict: [String: String]) {
            width = dict["s"].compactMap { UInt($0) } ?? 0
            height = dict["v"].compactMap { UInt($0) } ?? 0
            size = dict["S"].compactMap { UInt($0) } ?? 0
            offset = dict["O"].compactMap { UInt($0) } ?? 0
            identifier = dict["i"].compactMap { UInt32($0) } ?? 0
            imageNumber = dict["I"].compactMap { UInt32($0) } ?? 0
            placement = dict["p"].compactMap { UInt32($0) } ?? 0

            // Not documented but inferred from
            /*
             So for example, you could send:

             <ESC>_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA<ESC>\<ESC>[c
             */
            if let verbosity = extractEnum(from: dict, key: "q", defaultValue: Verbosity.normal) {
                self.verbosity = verbosity
            } else {
                return nil
            }
            if let format = extractEnum(from: dict, key: "f", defaultValue: Format.raw32) {
                self.format = format
            } else {
                return nil
            }
            if let medium = extractEnum(from: dict, key: "t", defaultValue: Medium.direct) {
                self.medium = medium
            } else {
                return nil
            }
            if let compression = extractEnum(from: dict, key: "o", defaultValue: Compression.uncompressed) {
                self.compression = compression
            } else {
                return nil
            }
            if let more = extractEnum(from: dict, key: "m", defaultValue: More.finalChunk) {
                self.more = more
            } else {
                return nil
            }
        }
    }

    enum Category {
        case imageTransmission(ImageTransmission)
        case imageDisplay(ImageDisplay)
        case transmitAndDisplay(ImageTransmission, ImageDisplay)
        case animationFrameLoading(AnimationFrameLoading)
        case animationFrameComposition(AnimationFrameComposition)
        case animationControl(AnimationControl)
        case deleteImage(DeleteImage)
    }
    var category: Category

    struct ImageDisplay {
        enum CursorMovementPolicy: String {
            case moveCursorToAfterImage = "0"
            case doNotMoveCursor = "1"
        }
        enum CreateUnicodePlaceholder: String {
            case doNotCreate = "0"
            case createPlaceholder = "1"
        }

        var x: UInt32
        var y: UInt32
        var w: UInt32
        var h: UInt32
        var X: UInt32
        var Y: UInt32
        var c: UInt32
        var r: UInt32
        var cursorMovementPolicy: CursorMovementPolicy  // C
        var createUnicodePlaceholder: CreateUnicodePlaceholder
        var z: Int32
        var parentImageIdentifier: UInt32? // P — the purpose of this is undocumented
        var parentPlacement: UInt32? // Q
        var H: Int32
        var V: Int32
        var q: UInt32
        var identifier: UInt32  // i
        var number: UInt32 // I
        var placement: UInt32 // p

        init?(_ dict: [String: String]) {
            x = dict["x"].compactMap { UInt32($0) } ?? 0
            y = dict["y"].compactMap { UInt32($0) } ?? 0
            w = dict["w"].compactMap { UInt32($0) } ?? 0
            h = dict["h"].compactMap { UInt32($0) } ?? 0
            X = dict["X"].compactMap { UInt32($0) } ?? 0
            Y = dict["Y"].compactMap { UInt32($0) } ?? 0
            c = dict["c"].compactMap { UInt32($0) } ?? 0
            r = dict["r"].compactMap { UInt32($0) } ?? 0
            q = dict["q"].compactMap { UInt32($0) } ?? 0
            identifier = dict["i"].compactMap { UInt32($0) } ?? 0
            number = dict["I"].compactMap { UInt32($0) } ?? 0
            placement = dict["p"].compactMap { UInt32($0) } ?? 0
            if let cursorMovementPolicy = extractEnum(from: dict, key: "C", defaultValue: CursorMovementPolicy.moveCursorToAfterImage) {
                self.cursorMovementPolicy = cursorMovementPolicy
            } else {
                return nil
            }
            if let createUnicodePlaceholder = extractEnum(from: dict, key: "U", defaultValue: CreateUnicodePlaceholder.doNotCreate) {
                self.createUnicodePlaceholder = createUnicodePlaceholder
            } else {
                return nil
            }
            z = dict["z"].compactMap { Int32($0) } ?? 0
            parentImageIdentifier = dict["P"].compactMap { UInt32($0) }
            parentPlacement = dict["Q"].compactMap { UInt32($0) }
            H = dict["H"].compactMap { Int32($0) } ?? 0
            V = dict["V"].compactMap { Int32($0) } ?? 0
        }
    }

    struct AnimationFrameLoading {
        enum AnimationComposition: String {
            case fullAlphaBlend = "0"
            case simpleReplacement = "1"
        }
        // Region of image to replace
        var x: UInt32
        var y: UInt32
        var s: UInt32
        var v: UInt32

        // 1-based frame number to initialize with.
        var c: UInt32

        // Gives the 1-based frame number to edit.
        var r: UInt32

        // If positive, delay in milliseconds before displaying this frame.
        // If negative, skip over the frame without displaying it.
        // If 0, the spec doesn't say what to do.
        var z: Int32

        var animationComposition: AnimationComposition  // X

        // Background color including alpha channel.
        // For example: 0xff0000ff is opaque red. 0x00ff0088 is translucent green
        var Y: UInt32

        init?(_ dict: [String: String]) {
            x = dict["x"].compactMap { UInt32($0) } ?? 0
            y = dict["y"].compactMap { UInt32($0) } ?? 0
            s = dict["s"].compactMap { UInt32($0) } ?? 0
            v = dict["v"].compactMap { UInt32($0) } ?? 0
            c = dict["c"].compactMap { UInt32($0) } ?? 0
            r = dict["r"].compactMap { UInt32($0) } ?? 0
            z = dict["z"].compactMap { Int32($0) } ?? 0
            if let animationComposition = extractEnum(from: dict, key: "X", defaultValue: AnimationComposition.fullAlphaBlend) {
                self.animationComposition = animationComposition
            } else {
                return nil
            }
            Y = dict["Y"].compactMap { UInt32($0) } ?? 0
        }
    }

    struct AnimationFrameComposition {
        enum BlendingMode: String {
            case fullAlphaBlending = "0"
            case simplerOverwrite = "1"
        }

        var c: UInt32
        var r: UInt32
        var x: UInt32
        var y: UInt32
        var w: UInt32
        var h: UInt32
        var X: UInt32
        var Y: UInt32
        var blendingMode: BlendingMode  // C

        init?(_ dict: [String: String]) {
            c = dict["c"].compactMap { UInt32($0) } ?? 0
            r = dict["r"].compactMap { UInt32($0) } ?? 0
            x = dict["x"].compactMap { UInt32($0) } ?? 0
            y = dict["y"].compactMap { UInt32($0) } ?? 0
            w = dict["w"].compactMap { UInt32($0) } ?? 0
            h = dict["h"].compactMap { UInt32($0) } ?? 0
            X = dict["X"].compactMap { UInt32($0) } ?? 0
            Y = dict["Y"].compactMap { UInt32($0) } ?? 0
            if let blendingMode = extractEnum(from: dict, key: "C", defaultValue: BlendingMode.fullAlphaBlending) {
                self.blendingMode = blendingMode
            } else {
                return nil
            }
        }
    }

    struct AnimationControl {
        enum AnimationMode: String {
            case noMode = "0"
            case stop = "1"
            case runAndWait = "2"
            case runWithoutWaiting = "3"
        }

        var animationMode: AnimationMode  // s
        var r: UInt32
        var z: Int32
        var c: UInt32
        var v: UInt32
        var identifier: UInt32  // i

        init?(_ dict: [String: String]) {
            if let animationMode = extractEnum(from: dict, key: "s", defaultValue: AnimationMode.noMode) {
                self.animationMode = animationMode
            } else {
                return nil
            }
            r = dict["r"].compactMap { UInt32($0) } ?? 0
            z = dict["z"].compactMap { Int32($0) } ?? 0
            c = dict["c"].compactMap { UInt32($0) } ?? 0
            v = dict["v"].compactMap { UInt32($0) } ?? 0

            // Not documented but inferred from:
            /*
             The simplest is client driven animations, where the client transmits the frame data and then also instructs the terminal to make a particular frame the current frame. To change the current frame, use the c key:

             <ESC>_Ga=a,i=3,c=7<ESC>\
             */
            identifier = dict["i"].compactMap { UInt32($0) } ?? 0
        }
    }

    struct DeleteImage {
        var d: String
        var imageId: UInt32  // i
        var placementId: UInt32  // p
        var I: UInt32  // I
        var x: UInt32  // x
        var y: UInt32  // y
        var z: Int32  // z

        init?(_ dict: [String: String]) {
            d = dict["d"] ?? "a"
            imageId = dict["i"].compactMap { UInt32($0) } ?? 0
            placementId = dict["p"].compactMap { UInt32($0) } ?? 0
            I = dict["I"].compactMap { UInt32($0) } ?? 0
            x = dict["x"].compactMap { UInt32($0) } ?? 0
            y = dict["y"].compactMap { UInt32($0) } ?? 0
            z = dict["z"].compactMap { Int32($0) } ?? 0
        }
    }

    @objc(initWithAPCString:)
    init?(_ string: String) {
        let parts = string.components(separatedBy: ";")
        guard parts.count >= 1 else {
            return nil
        }
        let controls = parts[0].components(separatedBy: ",")
        let dict = controls.reduce(into: [String: String]()) { partialResult, kvp in
            guard let (key, value) = kvp.keyValuePair("=") else {
                return
            }
            partialResult[String(key)] = String(value)
        }
        if let action = extractEnum(from: dict, key: "a", defaultValue: Action.transmit) {
            self.action = action
        } else {
            return nil
        }

        let category: Category? =
            switch action {
            case .animationFrame:  // transmit data for animation frames
                AnimationFrameLoading(dict).compactMap { afl in
                    Category.animationFrameLoading(afl)
                }
            case .query, .transmit:
                ImageTransmission(dict).map { Category.imageTransmission($0) }
            case .transmitAndDisplay:  // transmit data and display image
                ImageTransmission(dict).compactMap { tx in
                    ImageDisplay(dict).map { disp in
                        Category.transmitAndDisplay(tx, disp)
                    }
                }
            case .put:  // put (display) previous transmitted image
                ImageDisplay(dict).map { Category.imageDisplay($0) }
            case .delete:  // delete image
                DeleteImage(dict).map { Category.deleteImage($0) }
            case .controlAnimation:  // control animation
                AnimationControl(dict).map { Category.animationControl($0) }
            case .compose:  // compose animation frames
                AnimationFrameComposition(dict).map { Category.animationFrameComposition($0) }
            }
        if let category {
            self.category = category
        } else {
            return nil
        }
        payload = parts.count > 1 ? parts[1] : ""
    }
}
