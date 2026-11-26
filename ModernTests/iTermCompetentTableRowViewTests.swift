//
//  iTermCompetentTableRowViewTests.swift
//  ModernTests
//
//  Characterization tests for the two row views of
//  iTermCompetentTableRowView.{h,m}: iTermCompetentTableRowView, which
//  draws its selection dark gray in a window whose appearance is vibrant
//  dark, and iTermBigSurTableRowView, a plain NSTableRowView subclass that
//  several tables make by name. Written against the Objective-C runtime so
//  they run unchanged against Swift classes with the same runtime names.
//  Windows are made but never ordered in; drawing goes to an offscreen
//  bitmap.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class iTermCompetentTableRowViewTests: XCTestCase {
    private let competentName = "iTermCompetentTableRowView"
    private let bigSurName = "iTermBigSurTableRowView"
    private let frame = NSRect(x: 0, y: 0, width: 8, height: 8)

    private func rowViewClass(_ name: String) -> NSTableRowView.Type? {
        return NSClassFromString(name) as? NSTableRowView.Type
    }

    private func ownMethods(_ cls: AnyClass) -> [String: String] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            return [:]
        }
        defer { free(methods) }
        return Dictionary(uniqueKeysWithValues: (0..<Int(count)).map {
            (NSStringFromSelector(method_getName(methods[$0])),
             method_getTypeEncoding(methods[$0]).map { String(cString: $0) } ?? "")
        })
    }

    // Key-value coding finds the method -it_dark by the key's name.
    private func itDark(_ view: NSView) -> Bool {
        XCTAssertNotNil(class_getInstanceMethod(type(of: view), NSSelectorFromString("it_dark")))
        return (view.value(forKey: "it_dark") as? Bool) ?? false
    }

    // A window that is never ordered in, holding the view.
    private func window(appearance: NSAppearance.Name?, holding view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        if let appearance {
            window.appearance = NSAppearance(named: appearance)
        }
        window.contentView?.addSubview(view)
        return window
    }

    private func render(_ body: () -> Void) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(frame.width),
                                         pixelsHigh: Int(frame.height),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        body()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func bytes(_ rep: NSBitmapImageRep?) -> Data? {
        guard let rep, let data = rep.bitmapData else {
            return nil
        }
        return Data(bytes: data, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    func testClassesExistUnderTheirObjectiveCNamesWithTheirSuperclass() {
        for name in [competentName, bigSurName] {
            guard let cls = rowViewClass(name) else {
                XCTFail("no class \(name)")
                continue
            }
            XCTAssertTrue(class_getSuperclass(cls) === NSTableRowView.self, name)
        }
    }

    func testSelectorsAndEncodings() {
        guard let competent = rowViewClass(competentName),
              let bigSur = rowViewClass(bigSurName) else {
            XCTFail("no class")
            return
        }
        let own = ownMethods(competent)
        XCTAssertEqual(own["it_dark"], "B16@0:8")
        XCTAssertEqual(own["drawSelectionInRect:"], "v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16")
        // iTermBigSurTableRowView adds no method of its own (initializers
        // inherited by a Swift class aside).
        XCTAssertEqual(Set(ownMethods(bigSur).keys).subtracting(["initWithFrame:", "initWithCoder:", "init"]), [])
    }

    func testBigSurMadeWithInitWithFrame() {
        guard let cls = rowViewClass(bigSurName) else {
            XCTFail("no class")
            return
        }
        let view = cls.init(frame: .zero)
        XCTAssertEqual(NSStringFromClass(type(of: view)), bigSurName)
        XCTAssertEqual(view.frame, .zero)
    }

    func testItDarkWithoutAWindowIsNo() {
        guard let cls = rowViewClass(competentName) else {
            XCTFail("no class")
            return
        }
        XCTAssertFalse(itDark(cls.init(frame: frame)))
    }

    func testItDarkFollowsTheWindowsAppearance() {
        guard let cls = rowViewClass(competentName) else {
            XCTFail("no class")
            return
        }
        let cases: [(NSAppearance.Name?, Bool)] = [(nil, false),
                                                   (.aqua, false),
                                                   (.darkAqua, false),
                                                   (.vibrantLight, false),
                                                   (.vibrantDark, true)]
        for (appearance, expected) in cases {
            let view = cls.init(frame: frame)
            let window = self.window(appearance: appearance, holding: view)
            XCTAssertEqual(itDark(view), expected, String(describing: appearance))
            XCTAssertFalse(window.isVisible)
        }
    }

    // In a vibrant dark window, a selection is filled dark gray.
    func testDrawSelectionInVibrantDarkFillsDarkGray() {
        guard let cls = rowViewClass(competentName) else {
            XCTFail("no class")
            return
        }
        let view = cls.init(frame: frame)
        view.isSelected = true
        let window = self.window(appearance: .vibrantDark, holding: view)
        let rep = render { view.drawSelection(in: frame) }
        let expected = NSColor.darkGray.usingColorSpace(.deviceRGB)
        for (x, y) in [(0, 0), (4, 4), (7, 7)] {
            guard let color = rep?.colorAt(x: x, y: y), let expected else {
                XCTFail("no color")
                return
            }
            XCTAssertEqual(color.redComponent, expected.redComponent, accuracy: 0.01)
            XCTAssertEqual(color.greenComponent, expected.greenComponent, accuracy: 0.01)
            XCTAssertEqual(color.blueComponent, expected.blueComponent, accuracy: 0.01)
            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
        }
        XCTAssertFalse(window.isVisible)
    }

    // Anywhere else, and with no highlight style even in vibrant dark, it
    // draws what NSTableRowView draws.
    func testDrawSelectionOtherwiseDrawsWhatSuperDraws() {
        guard let cls = rowViewClass(competentName) else {
            XCTFail("no class")
            return
        }
        let cases: [(NSAppearance.Name?, NSTableView.SelectionHighlightStyle)] = [(nil, .regular),
                                                                                (.aqua, .regular),
                                                                                (.vibrantDark, .none)]
        for (appearance, style) in cases {
            let view = cls.init(frame: frame)
            view.isSelected = true
            view.selectionHighlightStyle = style
            let plain = NSTableRowView(frame: frame)
            plain.isSelected = true
            plain.selectionHighlightStyle = style
            let window = self.window(appearance: appearance, holding: view)
            let otherWindow = self.window(appearance: appearance, holding: plain)
            XCTAssertEqual(bytes(render { view.drawSelection(in: frame) }),
                           bytes(render { plain.drawSelection(in: frame) }),
                           String(describing: appearance))
            XCTAssertFalse(window.isVisible)
            XCTAssertFalse(otherWindow.isVisible)
        }
    }
}
