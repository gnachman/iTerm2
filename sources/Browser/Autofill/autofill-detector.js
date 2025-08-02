;(function() {
    'use strict';
    
    // Prevent multiple script executions
    if (window.iTermAutofillDetectorLoaded) {
        return;
    }
    window.iTermAutofillDetectorLoaded = true;
    
    const handlerName = 'iTermAutofillHandler';
    const sessionSecret = "{{SECRET}}";

    // Include core autofill detection logic
    {{INCLUDE:autofill-core.js}}

    // Map to track which fields have buttons
    const fieldButtons = new WeakMap();
    
    // Create autofill button for a field
    function createAutofillButton(field, fieldType) {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.tabIndex = -1;
        btn.setAttribute('aria-label', `Autofill ${fieldType}`);
        btn.setAttribute('data-iterm-autofill', 'true');
        
        Object.assign(btn.style, {
            position: 'absolute',
            display: 'none',
            boxSizing: 'border-box',
            zIndex: '2147483647',
            borderRadius: '4px',
            border: '1px solid rgba(0,0,0,0.2)',
            background: '#fff',
            cursor: 'pointer',
            fontSize: '1em',
            lineHeight: '1',
            alignItems: 'center',
            justifyContent: 'center',
            padding: '0',
            margin: '0'
        });
        
        // Prevent focus stealing
        btn.addEventListener('mousedown', e => e.preventDefault());
        
        // Update theme
        function updateTheme() {
            if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
                btn.style.backgroundColor = '#2c2c2e';
                btn.style.border = '1px solid rgba(255,255,255,0.3)';
                btn.style.color = '#fff';
            } else {
                btn.style.backgroundColor = '#fff';
                btn.style.border = '1px solid rgba(0,0,0,0.2)';
                btn.style.color = '#000';
            }
        }
        updateTheme();
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', updateTheme);
        
        // Set icon based on field type
        const icons = {
            firstName: '👤',
            lastName: '👤',
            fullName: '👤',
            email: '✉️',
            phone: '📱',
            address1: '🏠',
            address2: '🏠',
            city: '🏙️',
            state: '📍',
            zip: '📮',
            country: '🌍',
            company: '🏢'
        };
        
        btn.textContent = icons[fieldType] || '📝';
        btn.title = `Autofill ${fieldType.replace(/([A-Z])/g, ' $1').toLowerCase()}`;
        
        // Handle click
        btn.addEventListener('click', e => {
            e.preventDefault();
            e.stopPropagation();
            
            // Collect all autofillable fields in the form
            const form = field.form;
            const fields = [];
            
            if (form) {
                // Find all fields in the same form
                const inputs = form.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]), select');
                inputs.forEach(input => {
                    const type = detectFieldType(input);
                    if (type) {
                        fields.push({
                            type: type,
                            name: input.name || null,
                            id: input.id || null,
                            value: input.value || ''
                        });
                    }
                });
            } else {
                // Just include the current field
                fields.push({
                    type: fieldType,
                    name: field.name || null,
                    id: field.id || null,
                    value: field.value || ''
                });
            }
            
            window.webkit.messageHandlers[handlerName].postMessage({
                type: 'autofillRequest',
                sessionSecret,
                activeField: {
                    type: fieldType,
                    name: field.name || null,
                    id: field.id || null
                },
                fields: fields
            });
        });
        
        // Set up mutation observer to handle field removal/hiding
        const observer = new MutationObserver(mutations => {
            let fieldRemoved = false;
            
            mutations.forEach(mutation => {
                // Check if the field was removed from DOM
                if (mutation.type === 'childList') {
                    mutation.removedNodes.forEach(node => {
                        if (node === field || (node.nodeType === Node.ELEMENT_NODE && node.contains(field))) {
                            fieldRemoved = true;
                        }
                    });
                }
                
                // Check if field visibility changed
                if (mutation.type === 'attributes' && 
                    (mutation.attributeName === 'style' || mutation.attributeName === 'class') &&
                    mutation.target === field) {
                    if (!isFieldInteractable(field)) {
                        fieldRemoved = true;
                    }
                }
            });
            
            if (fieldRemoved) {
                observer.disconnect();
                fieldButtons.delete(field);
                if (btn.parentNode) {
                    btn.parentNode.removeChild(btn);
                }
            }
        });
        
        // Observe the field's parent for removal and the field itself for attribute changes
        if (field.parentNode) {
            observer.observe(field.parentNode, { childList: true, subtree: true });
        }
        observer.observe(field, { attributes: true, attributeFilter: ['style', 'class'] });
        
        document.body.appendChild(btn);
        return btn;
    }
    
    // Position button relative to field
    function positionButton(btn, field) {
        const r = field.getBoundingClientRect();
        const emoji = btn.textContent;
        
        // Measure glyph size
        const meas = document.createElement('span');
        Object.assign(meas.style, {
            position: 'absolute',
            visibility: 'hidden',
            font: getComputedStyle(btn).font
        });
        meas.textContent = emoji;
        document.body.appendChild(meas);
        const dim = meas.getBoundingClientRect();
        document.body.removeChild(meas);
        const keyDim = Math.max(dim.width, dim.height);
        let side = Math.min(r.height * 0.8, keyDim * 1.5);  // 80% of field height max
        
        // Position button inside the right edge of the field
        const padding = 5;
        const topPosition = r.top + (r.height - side) / 2;
        const leftPosition = r.right - side - padding;
        
        // Position and size
        btn.style.width = `${side}px`;
        btn.style.height = `${side}px`;
        btn.style.top = `${window.scrollY + topPosition}px`;
        btn.style.left = `${window.scrollX + leftPosition}px`;
        btn.style.display = 'flex';
        
    }
    
    
    // Track if we've already scheduled a delayed rescan
    let delayedRescanScheduled = false;
    
    // Show/hide button for field
    function updateFieldButton(field) {
        const fieldType = detectFieldType(field);
        const isInteractable = isFieldInteractable(field);
        
        if (fieldType && isInteractable) {
            let btn = fieldButtons.get(field);
            if (!btn) {
                btn = createAutofillButton(field, fieldType);
                fieldButtons.set(field, btn);
            }
            positionButton(btn, field);
        } else {
            const btn = fieldButtons.get(field);
            if (btn) {
                btn.style.display = 'none';
            }
        }
    }
    
    // Hide all buttons
    function hideAllButtons() {
        document.querySelectorAll('[data-iterm-autofill]').forEach(btn => {
            btn.style.display = 'none';
        });
    }
    
    // Show buttons on all autofillable fields
    function showAllButtons() {
        const inputs = document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]), select');

        inputs.forEach(input => {
            const fieldType = detectFieldType(input);
            if (fieldType && isFieldInteractable(input)) {
                updateFieldButton(input);
            }
        });
    }
    
    // Event listeners
    let activeField = null;
    
    document.addEventListener('focusin', e => {
        const field = e.target;
        
        // Ignore focus on our buttons
        if (field.getAttribute('data-iterm-autofill')) {
            return;
        }
        
        // Update active field for scroll/resize handling
        if (field.tagName === 'INPUT' || field.tagName === 'SELECT') {
            activeField = field;
            
            // Check if this field is newly detectable (for dynamically loaded content)
            const fieldType = detectFieldType(field);
            if (fieldType && isFieldInteractable(field) && !fieldButtons.has(field)) {
                updateFieldButton(field);
            }
        } else {
            activeField = null;
        }
    });
    
    document.addEventListener('focusout', e => {
        // Keep buttons visible, just update activeField
        setTimeout(() => {
            const newFocus = document.activeElement;
            if (!newFocus?.getAttribute('data-iterm-autofill') && 
                (!newFocus || (newFocus.tagName !== 'INPUT' && newFocus.tagName !== 'SELECT'))) {
                activeField = null;
            }
        }, 50);
    });
    
    // Update button positions on scroll/resize
    document.addEventListener('scroll', () => {
        showAllButtons();
    }, true);
    
    window.addEventListener('resize', () => {
        showAllButtons();
    });
    
    // Scan for autofillable fields on page load
    function scanForFields() {
        const inputs = document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]), select');
        const autofillableFields = [];
        
        inputs.forEach(input => {
            const fieldType = detectFieldType(input);
            if (fieldType) {
                autofillableFields.push({
                    type: fieldType,
                    element: input
                });
            }
        });
        
        // Show buttons on all autofillable fields
        showAllButtons();
    }
    
    
    // Clean up orphaned buttons (buttons whose fields no longer exist)
    function cleanupOrphanedButtons() {
        const allButtons = document.querySelectorAll('[data-iterm-autofill]');
        let cleanedCount = 0;
        const fieldsToDelete = [];
        
        allButtons.forEach(btn => {
            // Find the field this button belongs to
            let fieldFound = false;
            for (const [field, button] of fieldButtons) {
                if (button === btn) {
                    // Check if field still exists and is interactable
                    if (document.contains(field) && isFieldInteractable(field)) {
                        fieldFound = true;
                    } else {
                        // Field is gone or hidden, mark for cleanup
                        fieldsToDelete.push(field);
                        cleanedCount++;
                    }
                    break;
                }
            }
            
            if (!fieldFound) {
                // Button has no associated field, remove it
                if (btn.parentNode) {
                    btn.parentNode.removeChild(btn);
                    cleanedCount++;
                }
            }
        });
        
        // Clean up the WeakMap entries after iteration
        fieldsToDelete.forEach(field => {
            const btn = fieldButtons.get(field);
            if (btn && btn.parentNode) {
                btn.parentNode.removeChild(btn);
            }
            fieldButtons.delete(field);
        });
        
    }
    
    // Set up document-level mutation observer for major DOM changes
    const documentObserver = new MutationObserver(mutations => {
        let majorChange = false;
        
        mutations.forEach(mutation => {
            // Look for significant DOM changes (forms being replaced)
            if (mutation.type === 'childList' && mutation.removedNodes.length > 0) {
                mutation.removedNodes.forEach(node => {
                    if (node.nodeType === Node.ELEMENT_NODE) {
                        // If a form or container with inputs was removed
                        if (node.tagName === 'FORM' || 
                            node.querySelector('input, select') ||
                            node.querySelectorAll('input, select').length > 2) {
                            majorChange = true;
                        }
                    }
                });
            }
        });
        
        if (majorChange) {
            // More aggressive cleanup - remove all buttons and clear the map
            try {
                const allButtons = document.querySelectorAll('[data-iterm-autofill]');

                // First, clear the WeakMap by finding all fields that have buttons
                const fieldsWithButtons = [];
                const allInputs = document.querySelectorAll('input, select');
                allInputs.forEach(field => {
                    if (fieldButtons.has(field)) {
                        fieldsWithButtons.push(field);
                    }
                });

                // Remove buttons from DOM and clear WeakMap entries
                allButtons.forEach(btn => {
                    if (btn.parentNode) {
                        btn.parentNode.removeChild(btn);
                    }
                });
                
                // Clear WeakMap entries
                fieldsWithButtons.forEach(field => {
                    fieldButtons.delete(field);
                });

            } catch (error) {
                // Silently handle cleanup errors
            }
            
            // Small delay to let DOM stabilize, then rescan
            setTimeout(() => {
                showAllButtons();
            }, 200);
        }
    });
    
    // Observe document for major changes
    documentObserver.observe(document.body, { 
        childList: true, 
        subtree: true 
    });
    
    // Run initial scan
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', scanForFields);
    } else {
        scanForFields();
    }
    
    // Do a one-time rescan after 2 seconds to catch dynamically loaded fields
    if (!delayedRescanScheduled) {
        delayedRescanScheduled = true;
        setTimeout(() => {
            try {
                showAllButtons();
            } catch (error) {
                // Silently handle rescan errors
            }
        }, 2000);
    }
})();
