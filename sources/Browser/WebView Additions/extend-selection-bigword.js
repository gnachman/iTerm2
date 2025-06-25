(function() {
    var selection = window.getSelection();
    if (!selection.rangeCount) return false;
    var range = selection.getRangeAt(0);
    var text = document.body.innerText || document.body.textContent || "";
    var pos = {{START}} ? range.startOffset : range.endOffset;
    
    var regex = /\S+/g;
    var match;
    var matches = [];
    while ((match = regex.exec(text)) !== null) {
        matches.push({start: match.index, end: match.index + match[0].length});
    }
    
    if ({{FORWARD}}) {
        for (var i = 0; i < matches.length; i++) {
            if (matches[i].start > pos) {
                selection.modify("extend", "forward", "word");
                break;
            }
        }
    } else {
        for (var i = matches.length - 1; i >= 0; i--) {
            if (matches[i].end < pos) {
                selection.modify("extend", "backward", "word");
                break;
            }
        }
    }
    return true;
})();