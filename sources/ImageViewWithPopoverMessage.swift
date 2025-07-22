//
//  ImageViewWithPopoverMessage.swift
//  iTerm2
//
//  Created by George Nachman on 7/21/25.
//

@objc(iTermImageViewWithPopoverMessage)
class ImageViewWithPopoverMessage: NSImageView {

    override func mouseDown(with event: NSEvent) {
        it_showInformativeMessage(withMarkdown: toolTip)
    }

}

