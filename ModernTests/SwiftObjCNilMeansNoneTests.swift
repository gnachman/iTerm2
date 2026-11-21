//
//  SwiftObjCNilMeansNoneTests.swift
//  ModernTests
//
//  Objective-C passes nil to two Swift @objc parameters that were declared
//  non-optional (unit N6 of docs/swift-migration/nullability-triage.md). The
//  bridge turned the nil into an empty value, which the Swift code then took
//  for a real one. Unlike unit N5, the empty value was wrong here, so the
//  parameters are now optional and nil means "none". These tests call each
//  method with nil the way Objective-C does, through its implementation,
//  because Swift could not pass nil to the non-optional parameter.
//

import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import iTerm2SharedARC

final class SwiftObjCNilMeansNoneTests: XCTestCase {
    private func implementation<T>(of selector: Selector,
                                   in cls: AnyClass,
                                   as type: T.Type,
                                   file: StaticString = #filePath,
                                   line: UInt = #line) throws -> T {
        let method = try XCTUnwrap(class_getInstanceMethod(cls, selector),
                                   "\(NSStringFromSelector(selector)) not found",
                                   file: file,
                                   line: line)
        return unsafeBitCast(method_getImplementation(method), to: type)
    }

    // MARK: - PathSniffer

    // VT100ScreenMutableState passes its current working directory, which is
    // nil until a directory is known. The class keeps pwd as String? and skips
    // relative candidates when it is nil; the bridge made it "" instead, which
    // would resolve a relative candidate against the root of the file system.
    func testPathSnifferKeepsANilWorkingDirectory() throws {
        // The initializer only stores the extractor. An empty data source
        // stands in for a screen, whose line buffer trips an unrelated claim
        // under the nullability sanitizer.
        let extractor = iTermTextExtractor(dataSource: EmptyTextDataSource())

        typealias Init = @convention(c) (Unmanaged<AnyObject>,
                                         Selector,
                                         iTermTextExtractor,
                                         VT100GridCoordRange,
                                         AnyObject?,
                                         Int64,
                                         NSString?,
                                         Int32,
                                         DispatchQueue) -> Unmanaged<AnyObject>?
        let selector = NSSelectorFromString("initWithExtractor:range:remoteHost:offset:pwd:width:queue:")
        let initialize = try implementation(of: selector, in: PathSniffer.self, as: Init.self)
        // +alloc returns an owned reference, which the initializer consumes; it
        // returns an owned reference in turn.
        let allocated = try XCTUnwrap((PathSniffer.self as AnyObject).perform(NSSelectorFromString("alloc")))
        let result = try XCTUnwrap(initialize(allocated,
                                              selector,
                                              extractor,
                                              VT100GridCoordRange(),
                                              nil,
                                              0,
                                              nil,
                                              80,
                                              DispatchQueue(label: "test.sniffer.nil-pwd")))
        let sniffer = try XCTUnwrap(result.takeRetainedValue() as? PathSniffer)

        let pwd = try XCTUnwrap(Mirror(reflecting: sniffer).descendant("pwd"))
        XCTAssertNil(pwd as? String, "pwd is \(String(describing: pwd))")
    }

    // MARK: - ImageRegistry

    // An image code that nothing else in the test host allocates.
    private let imageCode = 0xFEDC

    override func tearDown() {
        ImageRegistry.instance.remove(code: imageCode)
        super.tearDown()
    }

    private func makeNativeImage() throws -> iTermImage {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                 pixelsWide: 4,
                                                 pixelsHigh: 4,
                                                 bitsPerSample: 8,
                                                 samplesPerPixel: 4,
                                                 hasAlpha: true,
                                                 isPlanar: false,
                                                 colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0,
                                                 bitsPerPixel: 0))
        let nsImage = NSImage(size: NSSize(width: 4, height: 4))
        nsImage.addRepresentation(rep)
        return try XCTUnwrap(iTermImage(nativeImage: nsImage))
    }

    // Calls -setData:forImage:code: with nil data, as SetDecodedImage does for
    // a native image, which has no encoded data.
    private func setNilData(image: iTermImage) throws {
        typealias SetData = @convention(c) (AnyObject, Selector, NSData?, iTermImage, Int) -> Void
        let selector = NSSelectorFromString("setData:forImage:code:")
        let setData = try implementation(of: selector, in: ImageRegistry.self, as: SetData.self)
        setData(ImageRegistry.instance, selector, nil, image, imageCode)
    }

    func testImageRegistryStoresNoDataForANativeImage() throws {
        ImageRegistry.instance.assign(code: imageCode, imageInfo: iTermImageInfo(code: unichar(imageCode)))
        let image = try makeNativeImage()

        try setNilData(image: image)

        let info = try XCTUnwrap(ImageRegistry.instance.info(for: imageCode))
        XCTAssertTrue(info.image === image, "Precondition: the image was set")
        let data: Data? = info.data
        XCTAssertNil(data, "data is \(String(describing: data))")
    }

    // What the empty data did that a user could see: saving a native image
    // under a .tiff name wrote an empty file, because the empty data was taken
    // for encoded image data instead of rendering the image.
    func testSavingANativeImageAsTIFFWritesTheImage() throws {
        ImageRegistry.instance.assign(code: imageCode, imageInfo: iTermImageInfo(code: unichar(imageCode)))
        try setNilData(image: try makeNativeImage())
        let info = try XCTUnwrap(ImageRegistry.instance.info(for: imageCode))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftObjCNilMeansNoneTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("image.tiff").path

        info.save(toFile: path)

        let saved = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(saved.count, 0)
        XCTAssertEqual((saved as NSData).uniformTypeIdentifierForImageData, UTType.tiff.identifier)
    }

    // Copying or dragging an image offers public.image when the data has no
    // recognized type. With no data there is nothing to offer; the empty data
    // offered zero bytes, and offering nil would raise in -setData:forType:.
    func testPasteboardOffersNoImageDataForANativeImage() throws {
        ImageRegistry.instance.assign(code: imageCode, imageInfo: iTermImageInfo(code: unichar(imageCode)))
        try setNilData(image: try makeNativeImage())
        let info = try XCTUnwrap(ImageRegistry.instance.info(for: imageCode))
        let type = NSPasteboard.PasteboardType(UTType.image.identifier)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()

        info.pasteboard(pasteboard, item: item, provideDataForType: type)

        let provided = item.data(forType: type)
        XCTAssertNil(provided, "provided \(String(describing: provided))")
    }

    // MARK: - Dragging an image without data

    // Cmd-dragging an image asks PTYTextView to drag it, and the text view
    // gives up when the image has no data. Now that a native image has nil data
    // instead of empty data, that is what happens for it: no drag starts. The
    // pasteboard item is fetched just before the drag session begins, so not
    // fetching it shows the drag did not begin. (An image with data would begin
    // a real, on-screen drag, so there is no counterpart test here.)
    func testDraggingAnImageWithoutDataStartsNoDrag() throws {
        let textView = try XCTUnwrap(PTYTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100)))
        let image = NoDataImageInfo()
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDragged,
                                                     location: .zero,
                                                     modifierFlags: .command,
                                                     timestamp: 0,
                                                     windowNumber: 0,
                                                     context: nil,
                                                     eventNumber: 0,
                                                     clickCount: 1,
                                                     pressure: 1))

        // -mouseHandler:dragImage:forEvent: is declared in a header Swift does
        // not see; it forwards to -_dragImage:forEvent:.
        typealias DragImage = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject, NSEvent) -> Void
        let selector = NSSelectorFromString("mouseHandler:dragImage:forEvent:")
        let dragImage = try implementation(of: selector, in: PTYTextView.self, as: DragImage.self)
        dragImage(textView, selector, nil, image, event)

        XCTAssertTrue(image.iconRequested, "Precondition: the text view looked at the image")
        XCTAssertFalse(image.pasteboardItemRequested)
    }
}

// A data source with no lines.
private final class EmptyTextDataSource: NSObject, iTermTextDataSource {
    func width() -> Int32 { 80 }
    func numberOfLines() -> Int32 { 0 }
    func totalScrollbackOverflow() -> Int64 { 0 }
    func screenCharArray(forLine line: Int32) -> ScreenCharArray { ScreenCharArray.emptyLine(ofLength: 80) }
    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray { screenCharArray(forLine: index) }
    func externalAttributeIndex(forLine y: Int32) -> (any iTermExternalAttributeIndexReading)? { nil }
    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? { block(screenCharArray(forLine: line)) }
    func date(forLine line: Int32) -> Date? { nil }
    func commandMark(at coord: VT100GridCoord, mustHaveCommand: Bool, range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> (any VT100ScreenMarkReading)? { nil }
    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata { iTermImmutableMetadataDefault() }
    func isFirstLine(ofBlock lineNumber: Int32) -> Bool { false }
}

// An image with a picture but no encoded data, which records what the text
// view asks of it.
private final class NoDataImageInfo: NSObject, iTermImageInfoReading {
    private(set) var iconRequested = false
    private(set) var pasteboardItemRequested = false
    private let icon = NSImage(size: NSSize(width: 4, height: 4))

    var image: iTermImage! { nil }
    var data: Data! { nil }
    var code: unichar { 0 }
    var pasteboardItem: NSPasteboardItem! {
        pasteboardItemRequested = true
        return NSPasteboardItem()
    }
    var broken = false
    var animated: Bool { false }
    var paused = false
    var uniqueIdentifier: String! { "" }
    var size = NSSize(width: 1, height: 1)
    var nameForNewSavedTempFile: String! { "" }
    var filename: String! { "" }
    var ready: Bool { true }

    func image(withCellSize cellSize: CGSize, scale: CGFloat) -> NSImage! {
        iconRequested = true
        return icon
    }
    func image(withCellSize cellSize: CGSize, timestamp: TimeInterval, scale: CGFloat) -> NSImage! {
        iconRequested = true
        return icon
    }
    func save(toFile filename: String!) {}
    func save(to item: iTermSavePanelItem!) {}
    func frame(forTimestamp timestamp: TimeInterval) -> Int32 { 0 }
    func pasteboard(_ pasteboard: NSPasteboard?,
                    item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {}
}
