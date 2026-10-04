//
//  NSFont+BijectionIdentifiable.swift
//  iTerm2SharedARC
//

import AppKit
import CoreText

// NSFont's -hash is not consistent with its -isEqual:, so fonts can't be dictionary keys. A font
// made by CTFontCreateCopyWithAttributes with an explicit matrix (as
// -it_fontByAddingToPointSize: does for Cmd-+ and Cmd--) has an identity-matrix attribute in its
// descriptor that -hash includes and -isEqual: ignores. Swift traps when such a key duplicates
// another during a dictionary resize.
//
// A font's identity is its descriptor's attributes, which include everything that changes how it
// renders (name, size, feature settings, variations), minus a matrix attribute that is just the
// identity transform.
extension NSFont: BijectionIdentifiable {
    struct BijectionIdentity: Hashable {
        // Name and size spread the hash. The attributes decide equality; NSDictionary's hash is
        // just its count.
        var fontName: String
        var pointSize: CGFloat
        var attributes: NSDictionary
    }

    var bijectionIdentity: AnyHashable {
        let attributes = NSMutableDictionary(dictionary: fontDescriptor.fontAttributes as NSDictionary)
        let matrixKey = kCTFontMatrixAttribute as NSString
        if let matrix = attributes[matrixKey] as? Data, Self.isIdentityMatrix(matrix) {
            attributes.removeObject(forKey: matrixKey)
        }
        return AnyHashable(BijectionIdentity(fontName: fontName,
                                             pointSize: pointSize,
                                             attributes: attributes))
    }

    private static func isIdentityMatrix(_ data: Data) -> Bool {
        guard data.count == MemoryLayout<CGAffineTransform>.size else {
            return false
        }
        let transform = data.withUnsafeBytes { $0.loadUnaligned(as: CGAffineTransform.self) }
        return transform == .identity
    }
}
