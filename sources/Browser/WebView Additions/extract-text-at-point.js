(function() {
    var x = {{X}};
    var y = {{Y}};
    var radius = {{RADIUS}};
    
    // Get the caret position at the clicked point
    var range = document.caretRangeFromPoint(x, y);
    if (!range) return { before: "", after: "" };
    
    var container = range.startContainer;
    var offset = range.startOffset;
    
    // Helper function to get visible text from a node
    function getVisibleText(node) {
        if (node.nodeType === Node.TEXT_NODE) {
            return node.textContent;
        }
        if (node.nodeType === Node.ELEMENT_NODE) {
            var style = window.getComputedStyle(node);
            if (style.display === 'none' || style.visibility === 'hidden') {
                return '';
            }
            // Check if this is a block-level element
            if (style.display === 'block' || node.tagName === 'BR' || 
                node.tagName === 'P' || node.tagName === 'DIV' || 
                node.tagName === 'H1' || node.tagName === 'H2' || 
                node.tagName === 'H3' || node.tagName === 'H4' || 
                node.tagName === 'H5' || node.tagName === 'H6') {
                return '\n';
            }
        }
        return '';
    }
    
    // Collect text before the point
    var beforeText = '';
    var linesBefore = 0;
    var walker = document.createTreeWalker(
        document.body,
        NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
        null,
        false
    );
    
    // Position walker at current node
    walker.currentNode = container;
    
    // Collect text from current node before offset
    if (container.nodeType === Node.TEXT_NODE) {
        var currentText = container.textContent.substring(0, offset);
        beforeText = currentText;
        linesBefore += (currentText.match(/\n/g) || []).length;
    }
    
    // Walk backwards collecting text
    while (linesBefore < radius && walker.previousNode()) {
        var node = walker.currentNode;
        var text = getVisibleText(node);
        beforeText = text + beforeText;
        linesBefore += (text.match(/\n/g) || []).length;
        
        if (linesBefore >= radius) {
            // Trim to exactly radius lines
            var lines = beforeText.split('\n');
            if (lines.length > radius) {
                beforeText = lines.slice(-radius).join('\n');
            }
            break;
        }
    }
    
    // Collect text after the point
    var afterText = '';
    var linesAfter = 0;
    
    // Reset walker
    walker = document.createTreeWalker(
        document.body,
        NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
        null,
        false
    );
    walker.currentNode = container;
    
    // Collect text from current node after offset
    if (container.nodeType === Node.TEXT_NODE) {
        var currentText = container.textContent.substring(offset);
        afterText = currentText;
        linesAfter += (currentText.match(/\n/g) || []).length;
    }
    
    // Walk forwards collecting text
    while (linesAfter < radius && walker.nextNode()) {
        var node = walker.currentNode;
        var text = getVisibleText(node);
        afterText = afterText + text;
        linesAfter += (text.match(/\n/g) || []).length;
        
        if (linesAfter >= radius) {
            // Trim to exactly radius lines
            var lines = afterText.split('\n');
            if (lines.length > radius) {
                afterText = lines.slice(0, radius).join('\n');
            }
            break;
        }
    }
    
    return {
        before: beforeText,
        after: afterText
    };
})();