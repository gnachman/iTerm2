(function() {
    var x = {{X}};
    var y = {{Y}};
    var selection = window.getSelection();
    
    if (!selection.rangeCount) return false;
    
    var range = selection.getRangeAt(0);
    var targetRange = document.caretRangeFromPoint(x, y);
    if (!targetRange) return false;
    
    // Compare the clicked point with the current selection boundaries
    // to determine if it's before the start or after the end
    var clickedNode = targetRange.startContainer;
    var clickedOffset = targetRange.startOffset;
    
    // Create ranges for comparison
    var startRange = document.createRange();
    startRange.setStart(range.startContainer, range.startOffset);
    startRange.setEnd(range.startContainer, range.startOffset);
    
    var endRange = document.createRange();
    endRange.setStart(range.endContainer, range.endOffset);
    endRange.setEnd(range.endContainer, range.endOffset);
    
    var clickRange = document.createRange();
    clickRange.setStart(clickedNode, clickedOffset);
    clickRange.setEnd(clickedNode, clickedOffset);
    
    // Use Range.compareBoundaryPoints to determine position
    // -1 means clicked point is before, 1 means after
    var compareToStart = clickRange.compareBoundaryPoints(Range.START_TO_START, startRange);
    var compareToEnd = clickRange.compareBoundaryPoints(Range.START_TO_START, endRange);
    
    if (compareToStart < 0) {
        // Clicked point is before the start - extend start
        range.setStart(clickedNode, clickedOffset);
    } else if (compareToEnd > 0) {
        // Clicked point is after the end - extend end
        range.setEnd(clickedNode, clickedOffset);
    } else {
        // Clicked point is within the selection
        // Determine which boundary is closer in document order
        var startToClick = document.createRange();
        startToClick.setStart(range.startContainer, range.startOffset);
        startToClick.setEnd(clickedNode, clickedOffset);
        
        var clickToEnd = document.createRange();
        clickToEnd.setStart(clickedNode, clickedOffset);
        clickToEnd.setEnd(range.endContainer, range.endOffset);
        
        // Compare the text content length as a proxy for distance
        if (startToClick.toString().length < clickToEnd.toString().length) {
            range.setStart(clickedNode, clickedOffset);
        } else {
            range.setEnd(clickedNode, clickedOffset);
        }
    }
    
    selection.removeAllRanges();
    selection.addRange(range);
    return true;
})();