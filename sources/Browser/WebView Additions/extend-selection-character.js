(function() {
    var selection = window.getSelection();
    if (!selection.rangeCount) return false;
    var range = selection.getRangeAt(0);
    var node = {{START}} ? range.startContainer : range.endContainer;
    var offset = {{START}} ? range.startOffset : range.endOffset;
    
    function getTextLength(node) {
        if (node.nodeType === Node.TEXT_NODE) {
            return node.nodeValue.length;
        }
        return node.textContent.length;
    }
    
    function findNextTextNode(node) {
        var walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            null,
            false
        );
        walker.currentNode = node;
        return walker.nextNode();
    }
    
    function findPrevTextNode(node) {
        var walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            null,
            false
        );
        walker.currentNode = node;
        return walker.previousNode();
    }
    
    if ({{FORWARD}}) {
        if (offset < getTextLength(node)) {
            offset++;
        } else {
            var nextNode = findNextTextNode(node);
            if (nextNode) {
                node = nextNode;
                offset = 1;
            }
        }
    } else {
        if (offset > 0) {
            offset--;
        } else {
            var prevNode = findPrevTextNode(node);
            if (prevNode) {
                node = prevNode;
                offset = getTextLength(node) - 1;
            }
        }
    }
    
    if ({{START}}) {
        range.setStart(node, offset);
    } else {
        range.setEnd(node, offset);
    }
    selection.removeAllRanges();
    selection.addRange(range);
    return true;
})();