//
//  DraggableNSBox.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/28/23.
//

import Cocoa

@objc
protocol DraggableNSBoxDelegate {
    func draggableBoxDidDrag(_ box: DraggableNSBox)
    func draggableBoxWillDrag(_ box: DraggableNSBox)
}

@objc
class DraggableNSBox: NSBox {
    @objc weak var delegate: DraggableNSBoxDelegate?
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        self.window?.performDrag(with: event)
        delegate?.draggableBoxWillDrag(self)
        dragging = true
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            dragging = false
            delegate?.draggableBoxDidDrag(self)
        }
        super.mouseUp(with: event)
    }
}

