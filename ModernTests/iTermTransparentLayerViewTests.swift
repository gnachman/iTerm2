//
//  iTermTransparentLayerViewTests.swift
//  ModernTests
//
//  Characterization tests for iTermTransparentLayerView, an NSView subclass that the
//  toast window controller makes with -init and uses to hold the size of the
//  toast's content. Made with -initWithFrame: (which -init calls), the view
//  is layer backed by a plain CALayer that is transparent and not opaque, and
//  the view reports itself as not opaque. It draws nothing of its own. Made
//  from a coder, it gets none of that setup. Everything goes through the
//  Objective-C runtime: the class is found by name. Nothing is put on screen;
//  the layer is rendered into an offscreen bitmap.
//

import XCTest
import ObjectiveC
import QuartzCore
@testable import iTerm2SharedARC

final class iTermTransparentLayerViewTests: XCTestCase {
    private let unitClassName = "iTermTransparentLayerView"

    private func viewClass() throws -> NSView.Type {
        return try XCTUnwrap(NSClassFromString(unitClassName) as? NSView.Type)
    }

    private func instanceMethodEncoding(_ cls: AnyClass, _ name: String) -> String? {
        guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)),
              let encoding = method_getTypeEncoding(method) else {
            return nil
        }
        return String(cString: encoding)
    }

    // The setup that -initWithFrame: does: a layer of exactly the CALayer
    // class (not the backing layer class AppKit would make), a transparent
    // background, and neither the layer nor the view opaque.
    private func assertSetUpByInitWithFrame(_ view: NSView,
                                            file: StaticString = #filePath,
                                            line: UInt = #line) {
        XCTAssertTrue(view.wantsLayer, file: file, line: line)
        guard let layer = view.layer else {
            XCTFail("no layer", file: file, line: line)
            return
        }
        XCTAssertTrue(type(of: layer) == CALayer.self, "\(type(of: layer))", file: file, line: line)
        XCTAssertFalse(layer.isOpaque, file: file, line: line)
        guard let background = layer.backgroundColor else {
            XCTFail("no background color", file: file, line: line)
            return
        }
        XCTAssertEqual(background.alpha, 0, file: file, line: line)
        XCTAssertFalse(view.isOpaque, file: file, line: line)
        XCTAssertFalse(view.isFlipped, file: file, line: line)
    }

    // MARK: - The runtime interface

    func testClassIsFoundByItsRuntimeNameWithItsSuperclass() throws {
        let cls = try viewClass()
        XCTAssertTrue(class_getSuperclass(cls) === NSView.self)
    }

    func testSelectorsAndEncodings() throws {
        let cls = try viewClass()
        XCTAssertEqual(instanceMethodEncoding(cls, "initWithFrame:"),
                       "@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16")
        XCTAssertEqual(instanceMethodEncoding(cls, "isOpaque"), "B16@0:8")
    }

    // MARK: - Initialization

    func testInitWithFrameSetsUpATransparentPlainLayer() throws {
        let frame = NSRect(x: 3, y: 4, width: 50, height: 20)
        let view = try viewClass().init(frame: frame)
        XCTAssertEqual(view.frame, frame)
        assertSetUpByInitWithFrame(view)
    }

    // The toast window controller makes the view with -init, which NSView
    // implements by calling -initWithFrame: with an empty rectangle, and then
    // sets its frame.
    func testInitGoesThroughInitWithFrame() throws {
        let cls = try viewClass()
        let view = try XCTUnwrap((cls as NSObject.Type).init() as? NSView)
        XCTAssertTrue(type(of: view) == cls)
        XCTAssertEqual(view.frame, .zero)
        assertSetUpByInitWithFrame(view)
        let frame = NSRect(x: 0, y: 0, width: 120, height: 48)
        view.frame = frame
        XCTAssertEqual(view.frame, frame)
        assertSetUpByInitWithFrame(view)
    }

    // A view decoded from an archive is made by NSView's -initWithCoder:,
    // which does none of the setup above: an archived plain view, decoded as
    // this class, has no layer.
    func testInitWithCoderDoesNotSetUpTheLayer() throws {
        let cls = try viewClass()
        let archived = try NSKeyedArchiver.archivedData(
            withRootObject: NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 10)),
            requiringSecureCoding: false)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archived)
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(cls, forClassName: "NSView")
        let decoded = try XCTUnwrap(unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSView)
        unarchiver.finishDecoding()
        XCTAssertTrue(type(of: decoded) == cls)
        XCTAssertEqual(decoded.frame, NSRect(x: 0, y: 0, width: 30, height: 10))
        XCTAssertFalse(decoded.wantsLayer)
        XCTAssertNil(decoded.layer)
        XCTAssertFalse(decoded.isOpaque)
    }

    // MARK: - Drawing

    // The view draws nothing and its layer's background is clear, so
    // rendering the layer into a transparent sRGB bitmap at scale 1 leaves
    // every pixel transparent.
    func testRenderingTheLayerLeavesEveryPixelTransparent() throws {
        let width = 16
        let height = 8
        let view = try viewClass().init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.appearance = NSAppearance(named: .aqua)
        let layer = try XCTUnwrap(view.layer)
        layer.contentsScale = 1
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil,
                                              width: width,
                                              height: height,
                                              bitsPerComponent: 8,
                                              bytesPerRow: width * 4,
                                              space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        layer.render(in: context)
        let image = try XCTUnwrap(context.makeImage())
        let rep = NSBitmapImageRep(cgImage: image)
        var visible = [String]()
        for y in 0..<height {
            for x in 0..<width where (rep.colorAt(x: x, y: y)?.alphaComponent ?? -1) != 0 {
                visible.append("\(x),\(y)")
            }
        }
        XCTAssertEqual(visible, [])
    }
}
