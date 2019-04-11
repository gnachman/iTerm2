//
//  StarTableViewCell.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Foundation

class StarImageView: NSImageView {
    @objc(hitTest:)
    public override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) ? self : nil
    }
}

class StarTableViewCell: NSView {
    static let width = 26
    static let emptyStarImage = Bundle(for: StarTableViewCell.self).image(forResource: NSImage.Name("EmptyStar"))!
    static let filledStarImage = Bundle(for: StarTableViewCell.self).image(forResource: NSImage.Name("FilledStar"))
    private let imageView = NSImageView(frame: NSRect(x: 0,
                                                      y: 0,
                                                      width: StarTableViewCell.emptyStarImage.size.width,
                                                      height: StarTableViewCell.emptyStarImage.size.height))
    private var internalSelected = false
    public var selected: Bool {
        get {
            return internalSelected
        }
        set {
            internalSelected = newValue
            StarTableViewCell.filledStarImage?.isTemplate = true
            imageView.image = internalSelected ? StarTableViewCell.filledStarImage : StarTableViewCell.emptyStarImage
        }
    }

    init() {
        super.init(frame: NSRect.zero)

        imageView.image = StarTableViewCell.emptyStarImage
        if #available(macOS 10.14, *) {
            imageView.image?.isTemplate = true
            imageView.contentTintColor = NSColor.labelColor
        }
        addSubview(imageView)
        imageView.frame = NSRect(origin: NSPoint(x: bounds.size.width - StarTableViewCell.emptyStarImage.size.width,
                                                 y: (bounds.size.height - StarTableViewCell.emptyStarImage.size.height) / 2.0),
                                 size: StarTableViewCell.emptyStarImage.size)
    }

    @objc(resizeSubviewsWithOldSize:)
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        imageView.frame = NSRect(origin: NSPoint(x: 0,
                                                 y: (bounds.size.height - StarTableViewCell.emptyStarImage.size.height) / 2.0),
                                 size: StarTableViewCell.emptyStarImage.size)
    }

    required init?(coder decoder: NSCoder) {
        fatalError()
    }
}


