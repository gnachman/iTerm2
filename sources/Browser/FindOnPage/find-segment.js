// Represents a segment in the document - either text content or an iframe
class Segment {
    constructor(type, index) {
        this.type = type;           // 'text' or 'iframe'
        this.index = index;         // Position in parent's segment array
    }
}

