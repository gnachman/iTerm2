(function() {
    var beforeCount = {{BEFORE_COUNT}};
    var afterCount = {{AFTER_COUNT}};
    var x = {{X}};
    var y = {{Y}};
    
    // Get the starting point
    var startRange = document.caretRangeFromPoint(x, y);
    if (!startRange) return false;
    
    var container = startRange.startContainer;
    var offset = startRange.startOffset;
    
    // Create a range for the selection
    var selectionRange = document.createRange();
    
    // Walk backwards to find the start of the selection
    var walker = document.createTreeWalker(
        document.body,
        NodeFilter.SHOW_TEXT,
        null,
        false
    );
    
    walker.currentNode = container;
    var charsToGo = beforeCount;
    var startNode = container;
    var startOffset = offset;
    
    // Handle current node first
    if (container.nodeType === Node.TEXT_NODE) {
        if (offset >= charsToGo) {
            startOffset = offset - charsToGo;
            charsToGo = 0;
        } else {
            charsToGo -= offset;
            startOffset = 0;
            
            // Walk backwards
            while (charsToGo > 0 && walker.previousNode()) {
                var node = walker.currentNode;
                if (node.nodeType === Node.TEXT_NODE) {
                    var textLength = node.textContent.length;
                    if (textLength >= charsToGo) {
                        startNode = node;
                        startOffset = textLength - charsToGo;
                        charsToGo = 0;
                    } else {
                        charsToGo -= textLength;
                    }
                }
            }
            
            if (charsToGo > 0) {
                // Reached beginning of document
                var firstText = document.createTreeWalker(
                    document.body,
                    NodeFilter.SHOW_TEXT,
                    null,
                    false
                ).nextNode();
                if (firstText) {
                    startNode = firstText;
                    startOffset = 0;
                }
            }
        }
    }
    
    // Set the start of the range
    selectionRange.setStart(startNode, startOffset);
    
    // Walk forwards to find the end of the selection
    walker = document.createTreeWalker(
        document.body,
        NodeFilter.SHOW_TEXT,
        null,
        false
    );
    
    walker.currentNode = container;
    charsToGo = afterCount;
    var endNode = container;
    var endOffset = offset;
    
    // Handle current node first
    if (container.nodeType === Node.TEXT_NODE) {
        var remainingLength = container.textContent.length - offset;
        if (remainingLength >= charsToGo) {
            endOffset = offset + charsToGo;
            charsToGo = 0;
        } else {
            charsToGo -= remainingLength;
            endOffset = container.textContent.length;
            
            // Walk forwards
            while (charsToGo > 0 && walker.nextNode()) {
                var node = walker.currentNode;
                if (node.nodeType === Node.TEXT_NODE) {
                    var textLength = node.textContent.length;
                    if (textLength >= charsToGo) {
                        endNode = node;
                        endOffset = charsToGo;
                        charsToGo = 0;
                    } else {
                        charsToGo -= textLength;
                        endNode = node;
                        endOffset = textLength;
                    }
                }
            }
        }
    }
    
    // Set the end of the range
    selectionRange.setEnd(endNode, endOffset);
    
    // Apply the selection
    var selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(selectionRange);
    
    return true;
})();