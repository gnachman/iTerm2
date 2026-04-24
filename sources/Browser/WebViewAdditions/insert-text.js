(function() {
    var activeElement = document.activeElement;
    if (activeElement && (activeElement.tagName === 'INPUT' || 
                          activeElement.tagName === 'TEXTAREA' || 
                          activeElement.contentEditable === 'true')) {
        // Try execCommand first
        if (document.execCommand('insertText', false, "{{TEXT}}")) {
            return true;
        }
        
        // Fallback: manually insert text
        if (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA') {
            var start = activeElement.selectionStart;
            var end = activeElement.selectionEnd;
            var value = activeElement.value;
            activeElement.value = value.substring(0, start) + "{{TEXT}}" + value.substring(end);
            activeElement.selectionStart = activeElement.selectionEnd = start + "{{TEXT}}".length;
            activeElement.dispatchEvent(new Event('input', { bubbles: true }));
            return true;
        }
    }
    return false;
})();