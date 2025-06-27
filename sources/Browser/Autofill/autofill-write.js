(function() {
    const fieldId = "{{FIELD_ID}}";
    const fieldName = "{{FIELD_NAME}}";
    const value = {{VALUE}};
    
    // Find field by ID first, then by name
    let field = null;
    
    if (fieldId) {
        field = document.getElementById(fieldId);
    }
    
    if (!field && fieldName) {
        field = document.querySelector(`input[name="${fieldName}"], select[name="${fieldName}"]`);
    }
    
    if (!field) {
        return false;
    }
    
    // Check if field is enabled and visible
    if (field.disabled || field.readOnly) {
        return false;
    }
    
    const style = window.getComputedStyle(field);
    if (style.display === 'none' || style.visibility === 'hidden' || field.offsetParent === null) {
        return false;
    }
    
    // Fill the field
    field.focus();
    
    if (field.tagName === 'SELECT') {
        // For select elements, try to match by value first, then by text
        let matched = false;
        
        // Try exact value match first
        for (let option of field.options) {
            if (option.value === value) {
                field.value = value;
                matched = true;
                break;
            }
        }
        
        // If no exact value match, try to match by option text
        if (!matched) {
            for (let option of field.options) {
                if (option.text === value || option.text.includes(value)) {
                    field.value = option.value;
                    matched = true;
                    break;
                }
            }
        }
        
        if (!matched) {
            return false;
        }
    } else {
        field.value = value;
    }
    
    field.dispatchEvent(new Event('input', { bubbles: true }));
    field.dispatchEvent(new Event('change', { bubbles: true }));
    
    // Add highlight animation
    (function injectHighlightStyle() {
        if (document.getElementById('iterm2-autofill-highlight-style')) return;
        const style = document.createElement('style');
        style.id = 'iterm2-autofill-highlight-style';
        style.textContent = `
            @keyframes autofillHighlight {
                0%   { box-shadow: 0 0 0px rgba(0, 122, 255, 0.0); }
                50%  { box-shadow: 0 0 8px rgba(0, 122, 255, 1.0); }
                100% { box-shadow: 0 0 0px rgba(0, 122, 255, 0.0); }
            }
            .autofill-highlight {
                animation: autofillHighlight 1s ease-in-out;
            }
        `;
        document.head.appendChild(style);
    })();
    
    field.classList.add('autofill-highlight');
    field.addEventListener('animationend', function _onAnim() {
        field.classList.remove('autofill-highlight');
        field.removeEventListener('animationend', _onAnim);
    });
    
    return true;
})();