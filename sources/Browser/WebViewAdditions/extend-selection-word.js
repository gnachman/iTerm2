(function() {
    var selection = window.getSelection();
    if (!selection.rangeCount) return false;
    
    var range = selection.getRangeAt(0);
    var isStart = {{START}};
    var isForward = {{FORWARD}};
    
    // Create a new range to work with
    var newRange = range.cloneRange();
    
    // Collapse to the appropriate end
    if (isStart) {
        newRange.collapse(true); // collapse to start
    } else {
        newRange.collapse(false); // collapse to end
    }
    
    // Create a temporary selection to use modify()
    var tempSelection = window.getSelection();
    tempSelection.removeAllRanges();
    tempSelection.addRange(newRange);
    
    // Modify by word
    tempSelection.modify("extend", isForward ? "forward" : "backward", "word");
    
    // Get the modified range
    if (tempSelection.rangeCount > 0) {
        var modifiedRange = tempSelection.getRangeAt(0);
        
        // For backward movement, we need to use the start of the modified range
        // For forward movement, we use the end
        var newContainer, newOffset;
        if (isForward) {
            newContainer = modifiedRange.endContainer;
            newOffset = modifiedRange.endOffset;
        } else {
            newContainer = modifiedRange.startContainer;
            newOffset = modifiedRange.startOffset;
        }
        
        // Update the original range
        if (isStart) {
            range.setStart(newContainer, newOffset);
        } else {
            range.setEnd(newContainer, newOffset);
        }
        
        // Apply the updated range
        selection.removeAllRanges();
        selection.addRange(range);
    }
    
    return true;
})();