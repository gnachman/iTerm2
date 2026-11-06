//
//  MarkdownImagePopover.swift
//  iTerm2SharedARC
//
//  Shows an image referenced by Markdown in a porthole when its placeholder is
//  clicked. The popover floats over the terminal, so showing the image doesn't
//  change the layout of the text.
//

import AppKit

enum MarkdownImagePopover {
    private static let maximumSize = NSSize(width: 800, height: 600)
    private static let padding = CGFloat(8)

    static func show(_ reference: MarkdownImageReference,
                     image: NSImage?,
                     relativeTo rect: NSRect,
                     of view: NSView) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = contentViewController(reference, image: image)
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }

    private static func contentViewController(_ reference: MarkdownImageReference,
                                              image: NSImage?) -> NSViewController {
        let content: NSView
        if let image, image.size.width > 0, image.size.height > 0 {
            content = imageView(image, toolTip: reference.alt)
        } else {
            content = failureLabel(reference)
        }
        let container = NSView(frame: NSRect(x: 0,
                                             y: 0,
                                             width: content.frame.width + padding * 2,
                                             height: content.frame.height + padding * 2))
        content.frame.origin = NSPoint(x: padding, y: padding)
        container.addSubview(content)
        let viewController = NSViewController()
        viewController.view = container
        return viewController
    }

    private static func imageView(_ image: NSImage, toolTip: String) -> NSView {
        let screenSize = NSScreen.main?.visibleFrame.size ?? maximumSize
        let limit = NSSize(width: min(maximumSize.width, screenSize.width * 0.8),
                           height: min(maximumSize.height, screenSize.height * 0.8))
        let scale = min(1, limit.width / image.size.width, limit.height / image.size.height)
        let imageView = NSImageView(frame: NSRect(x: 0,
                                                  y: 0,
                                                  width: max(1, floor(image.size.width * scale)),
                                                  height: max(1, floor(image.size.height * scale))))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.toolTip = toolTip.isEmpty ? nil : toolTip
        return imageView
    }

    private static func failureLabel(_ reference: MarkdownImageReference) -> NSView {
        let label = NSTextField(wrappingLabelWithString: String(
            localized: "MarkdownPorthole.ImageUnavailable",
            defaultValue: "Couldn’t show “\(reference.source)”. Only images in files on this Mac can be shown, and web images are never downloaded.",
            comment: "Shown in a popover when an image in Markdown displayed in the terminal can't be shown. The placeholder is the image's path or URL as written in the Markdown."))
        label.preferredMaxLayoutWidth = 320
        label.frame.size = label.fittingSize
        return label
    }
}
