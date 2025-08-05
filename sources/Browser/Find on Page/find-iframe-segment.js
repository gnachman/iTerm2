class IframeSegment extends Segment {
    constructor(index, iframe, frameId) {
        super('iframe', index);
        this.iframe = iframe;        // The iframe DOM element
        this.frameId = frameId;      // ID from graph discovery
        this.bounds = null;
    }

    updateBounds() {
        this.bounds = _getBoundingClientRect.call(this.iframe);
    }

    containsPoint(x, y) {
        if (!this.bounds) this.updateBounds();
        return x >= this.bounds.left && x <= this.bounds.right &&
               y >= this.bounds.top && y <= this.bounds.bottom;
    }
}
