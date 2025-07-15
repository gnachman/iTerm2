;(function() {
    'use strict';
    
    // Prevent multiple script executions
    if (window.iTermAutofillDetectorLoaded) {
        console.debug("autofill detector already loaded, skipping");
        return;
    }
    window.iTermAutofillDetectorLoaded = true;
    
    const handlerName = 'iTermAutofillHandler';
    const sessionSecret = "{{SECRET}}";
    console.debug("autofill detector running");

    // Map to track which fields have buttons
    const fieldButtons = new WeakMap();
    
    // Common patterns for field detection
    const fieldPatterns = {
        firstName: {
            autocomplete: ['given-name'],
            names: ['fname', 'firstname', 'first-name', 'first_name', 'givenname', 'given_name'],
            ids: ['first-name', 'firstname', 'fname', 'given-name'],
            labels: ['first name', 'given name', 'fname', 'forename'],
            placeholders: ['first name', 'given name']
        },
        lastName: {
            autocomplete: ['family-name'],
            names: ['lname', 'lastname', 'last-name', 'last_name', 'surname', 'familyname', 'family_name'],
            ids: ['last-name', 'lastname', 'lname', 'surname', 'family-name'],
            labels: ['last name', 'family name', 'surname', 'lname'],
            placeholders: ['last name', 'family name', 'surname']
        },
        fullName: {
            autocomplete: ['name'],
            names: ['name', 'fullname', 'full-name', 'full_name', 'your-name', 'your_name'],
            ids: ['name', 'fullname', 'full-name', 'your-name'],
            labels: ['full name', 'name', 'your name'],
            placeholders: ['full name', 'your name', 'name']
        },
        email: {
            autocomplete: ['email'],
            type: 'email',
            names: ['email', 'e-mail', 'emailaddress', 'email-address', 'email_address'],
            ids: ['email', 'e-mail', 'emailaddress', 'email-address'],
            labels: ['email', 'e-mail', 'email address'],
            placeholders: ['email', 'your@email.com', 'example@email.com']
        },
        phone: {
            autocomplete: ['tel', 'tel-national'],
            type: 'tel',
            names: ['phone', 'telephone', 'tel', 'mobile', 'cell', 'phonenumber', 'phone-number', 'phone_number'],
            ids: ['phone', 'telephone', 'tel', 'mobile', 'phone-number'],
            labels: ['phone', 'telephone', 'mobile', 'cell', 'phone number'],
            placeholders: ['phone', 'telephone', '(555) 555-5555', '+1']
        },
        address1: {
            autocomplete: ['address-line1', 'street-address'],
            names: ['address', 'address1', 'address-1', 'address_1', 'street', 'streetaddress', 'street-address', 'street_address'],
            ids: ['address', 'address1', 'street-address', 'address-line1'],
            labels: ['address', 'street address', 'address line 1'],
            placeholders: ['street address', '123 main st']
        },
        address2: {
            autocomplete: ['address-line2'],
            names: ['address2', 'address-2', 'address_2', 'apt', 'apartment', 'suite', 'unit'],
            ids: ['address2', 'address-line2', 'apt', 'suite'],
            labels: ['address line 2', 'apartment', 'suite', 'unit', 'apt'],
            placeholders: ['apt', 'suite', 'unit', 'apartment']
        },
        city: {
            autocomplete: ['address-level2'],
            names: ['city', 'town', 'locality'],
            ids: ['city', 'town', 'locality'],
            labels: ['city', 'town'],
            placeholders: ['city', 'town']
        },
        state: {
            autocomplete: ['address-level1'],
            names: ['state', 'province', 'region', 'state-province'],
            ids: ['state', 'province', 'region'],
            labels: ['state', 'province', 'region', 'state/province'],
            placeholders: ['state', 'province']
        },
        zip: {
            autocomplete: ['postal-code'],
            names: ['zip', 'zipcode', 'zip-code', 'zip_code', 'postal', 'postalcode', 'postal-code', 'postal_code', 'postcode'],
            ids: ['zip', 'zipcode', 'postal-code', 'postcode'],
            labels: ['zip', 'postal code', 'zip code', 'postcode'],
            placeholders: ['zip', 'postal code', '12345']
        },
        country: {
            autocomplete: ['country', 'country-name'],
            names: ['country', 'countryname', 'country-name', 'country_name'],
            ids: ['country', 'country-name'],
            labels: ['country'],
            placeholders: ['country']
        },
        company: {
            autocomplete: ['organization'],
            names: ['company', 'organization', 'org', 'business', 'companyname', 'company-name', 'company_name'],
            ids: ['company', 'organization', 'company-name'],
            labels: ['company', 'organization', 'business name'],
            placeholders: ['company', 'organization']
        }
    };
    
    // Detect field type
    function detectFieldType(field) {
        if (!field || field.type === 'hidden' || field.type === 'submit' || field.type === 'button' || 
            field.type === 'checkbox' || field.type === 'radio') {
            return null;
        }
        
        // Check autocomplete attribute first (most reliable)
        const autocomplete = field.getAttribute('autocomplete')?.toLowerCase();
        if (autocomplete && autocomplete !== 'off') {
            for (const [type, pattern] of Object.entries(fieldPatterns)) {
                if (pattern.autocomplete?.includes(autocomplete)) {
                    return type;
                }
            }
        }
        
        // Check type attribute
        const fieldType = field.type?.toLowerCase();
        for (const [type, pattern] of Object.entries(fieldPatterns)) {
            if (pattern.type === fieldType) {
                return type;
            }
        }
        
        // Check name attribute
        const name = field.name?.toLowerCase() || '';
        for (const [type, pattern] of Object.entries(fieldPatterns)) {
            if (pattern.names?.some(n => name.includes(n))) {
                return type;
            }
        }
        
        // Check id attribute
        const id = field.id?.toLowerCase() || '';
        for (const [type, pattern] of Object.entries(fieldPatterns)) {
            if (pattern.ids?.some(i => id.includes(i))) {
                return type;
            }
        }
        
        // Check placeholder
        const placeholder = field.placeholder?.toLowerCase() || '';
        for (const [type, pattern] of Object.entries(fieldPatterns)) {
            if (pattern.placeholders?.some(p => placeholder.includes(p))) {
                return type;
            }
        }
        
        // Check associated label
        const labels = getFieldLabels(field);
        for (const label of labels) {
            const labelText = label.textContent?.toLowerCase() || '';
            for (const [type, pattern] of Object.entries(fieldPatterns)) {
                if (pattern.labels?.some(l => labelText.includes(l))) {
                    return type;
                }
            }
        }
        
        return null;
    }
    
    // Get all labels associated with a field
    function getFieldLabels(field) {
        const labels = [];
        
        // Direct label association
        if (field.id) {
            labels.push(...document.querySelectorAll(`label[for="${field.id}"]`));
        }
        
        // Parent label
        let parent = field.parentElement;
        while (parent && parent !== document.body) {
            if (parent.tagName === 'LABEL') {
                labels.push(parent);
                break;
            }
            parent = parent.parentElement;
        }
        
        return labels;
    }
    
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
                console.debug(`Field ${field.id || field.name} was removed or hidden, cleaning up button`);
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
        
        // Debug log
        console.debug(`Button positioned for ${field.id || field.name}: top=${window.scrollY + topPosition} (scrollY=${window.scrollY} + ${topPosition}), left=${window.scrollX + leftPosition} (scrollX=${window.scrollX} + ${leftPosition}), size=${side}`);
    }
    
    // Check if field is truly visible and user-interactable
    function isFieldInteractable(field) {
        if (!field.offsetParent || field.disabled || field.readOnly) {
            return false;
        }
        
        const rect = field.getBoundingClientRect();
        const style = getComputedStyle(field);
        
        // Check if field is hidden by CSS
        if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') {
            return false;
        }
        
        // Check if field has reasonable dimensions
        if (rect.width < 10 || rect.height < 10) {
            return false;
        }
        
        // Check if field is positioned way off screen (likely hidden autofill helper)
        // Be more aggressive about filtering off-screen fields
        if (rect.left > window.innerWidth || rect.top > window.innerHeight + 200 || 
            rect.right < 0 || rect.bottom < 0) {
            return false;
        }
        
        // Also check if the field looks like a hidden autofill helper field
        // These are typically very small and positioned in a row
        if (rect.height < 25 && rect.width < 200) {
            return false;
        }
        
        return true;
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
                console.debug(`Creating button for ${field.id || field.name} (type: ${fieldType})`);
                btn = createAutofillButton(field, fieldType);
                fieldButtons.set(field, btn);
            }
            positionButton(btn, field);
        } else {
            // Debug why field is being rejected
            if (fieldType && !isInteractable) {
                const rect = field.getBoundingClientRect();
                console.debug(`Field ${field.id || field.name} rejected: type=${fieldType}, rect=${rect.width}x${rect.height}, visible=${field.offsetParent !== null}`);
            }
            
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
        console.debug(`showAllButtons: checking ${inputs.length} inputs`);

        let buttonCount = 0;
        inputs.forEach(input => {
            const fieldType = detectFieldType(input);
            if (fieldType && isFieldInteractable(input)) {
                updateFieldButton(input);
                buttonCount++;
            }
        });
        console.debug(`showAllButtons: updated ${buttonCount} buttons`);
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
                console.debug(`Focused field ${field.id || field.name} is newly detectable, adding button`);
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
        
        console.debug(`Found ${autofillableFields.length} autofillable fields`);

        // Show buttons on all autofillable fields
        showAllButtons();
    }
    
    // Debug function to log all field detection and button status
    window.debugAutofillFields = function() {
        console.debug('=== AUTOFILL DEBUG ===');
        const inputs = document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]), select');
        console.debug(`Found ${inputs.length} total input/select elements`);

        // Remove any existing debug outlines
        document.querySelectorAll('.iterm-debug-outline').forEach(el => el.remove());
        
        // Add visual debug outlines to all form fields
        inputs.forEach((input, index) => {
            const rect = input.getBoundingClientRect();
            const outline = document.createElement('div');
            outline.className = 'iterm-debug-outline';
            outline.style.cssText = `
                position: absolute;
                top: ${window.scrollY + rect.top}px;
                left: ${window.scrollX + rect.left}px;
                width: ${rect.width}px;
                height: ${rect.height}px;
                border: 2px solid red;
                background: rgba(255, 0, 0, 0.1);
                pointer-events: none;
                z-index: 2147483646;
                box-sizing: border-box;
            `;
            
            // Add field number label
            const label = document.createElement('div');
            label.style.cssText = `
                position: absolute;
                top: -20px;
                left: 0;
                background: red;
                color: white;
                padding: 2px 6px;
                font-size: 12px;
                font-family: monospace;
                border-radius: 3px;
            `;
            label.textContent = `F${index + 1}`;
            outline.appendChild(label);
            
            document.body.appendChild(outline);
        });
        
        let detectedCount = 0;
        let buttonCount = 0;
        let visibleButtonCount = 0;
        
        inputs.forEach((input, index) => {
            const fieldType = detectFieldType(input);
            const isDetected = !!fieldType;
            const isEligible = fieldType && isFieldInteractable(input);
            const hasButton = fieldButtons.has(input);
            const button = fieldButtons.get(input);
            
            if (isDetected) detectedCount++;
            if (hasButton) buttonCount++;
            if (button && button.style.display === 'flex') visibleButtonCount++;
            
            const fieldRect = input.getBoundingClientRect();
            const fieldInfo = {
                tagName: input.tagName,
                type: input.type || 'N/A',
                id: input.id || 'N/A',
                name: input.name || 'N/A',
                autocomplete: input.getAttribute('autocomplete') || 'N/A',
                placeholder: input.placeholder || 'N/A',
                labels: getFieldLabels(input).map(l => l.textContent?.trim() || 'N/A'),
                detectedType: fieldType || 'NOT DETECTED',
                fieldPosition: `top:${fieldRect.top} left:${fieldRect.left} width:${fieldRect.width} height:${fieldRect.height}`,
                visible: input.offsetParent !== null,
                disabled: input.disabled,
                readOnly: input.readOnly,
                eligible: isEligible,
                hasButton: hasButton,
                buttonVisible: button ? button.style.display : 'N/A',
                buttonPosition: button ? `top:${button.style.top} left:${button.style.left}` : 'N/A'
            };
            console.debug(`Field ${index + 1}:`, JSON.stringify(fieldInfo, null, 2));
        });
        
        console.debug(`\nSUMMARY:`);
        console.debug(`- Total fields: ${inputs.length}`);
        console.debug(`- Detected as autofillable: ${detectedCount}`);
        console.debug(`- Have buttons created: ${buttonCount}`);
        console.debug(`- Buttons visible: ${visibleButtonCount}`);

        // Check for existing buttons in DOM
        const allButtons = document.querySelectorAll('[data-iterm-autofill]');
        console.debug(`- Autofill buttons in DOM: ${allButtons.length}`);

        allButtons.forEach((btn, index) => {
            const rect = btn.getBoundingClientRect();
            console.debug(`Button ${index + 1}: display=${btn.style.display}, position=${btn.style.top},${btn.style.left}, rect=${rect.top},${rect.left},${rect.width},${rect.height}`);
        });
        
        console.debug('=== END AUTOFILL DEBUG ===');
        console.debug('Red outlines show all form fields. Use window.clearAutofillDebug() to remove them.');
    };
    
    // Function to clear debug outlines
    window.clearAutofillDebug = function() {
        document.querySelectorAll('.iterm-debug-outline').forEach(el => el.remove());
        console.debug('Debug outlines cleared.');
    };
    
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
                        console.debug(`Cleaning up orphaned button for field ${field.id || field.name}`);
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
                    console.debug('Removed orphaned button with no associated field');
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
        
        if (cleanedCount > 0) {
            console.debug(`Cleaned up ${cleanedCount} orphaned buttons`);
        }
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
            console.debug('Major DOM change detected, cleaning up and rescanning');

            // More aggressive cleanup - remove all buttons and clear the map
            try {
                const allButtons = document.querySelectorAll('[data-iterm-autofill]');
                console.debug(`Removing ${allButtons.length} existing autofill buttons`);

                // First, clear the WeakMap by finding all fields that have buttons
                const fieldsWithButtons = [];
                const allInputs = document.querySelectorAll('input, select');
                allInputs.forEach(field => {
                    if (fieldButtons.has(field)) {
                        fieldsWithButtons.push(field);
                    }
                });
                
                console.debug(`Found ${fieldsWithButtons.length} fields with buttons in WeakMap`);

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
                
                console.debug(`Cleared ${fieldsWithButtons.length} entries from fieldButtons WeakMap`);

            } catch (error) {
                console.debug('Error during cleanup:', error);
            }
            
            // Small delay to let DOM stabilize, then rescan
            setTimeout(() => {
                console.debug('Rescanning for new fields after DOM change');
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
        console.debug(`Scheduling one-time rescan for URL: ${window.location.href}`);
        setTimeout(() => {
            console.debug(`Performing one-time rescan for URL: ${window.location.href}`);
            console.debug('This will reposition all existing buttons to handle layout changes');
            try {
                showAllButtons();
            } catch (error) {
                console.debug('Error during delayed rescan:', error);
            }
        }, 2000);
    }
})();
