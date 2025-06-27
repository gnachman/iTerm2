;(function() {
    'use strict';
    const handlerName = 'iTermAutofillHandler';
    const sessionSecret = "{{SECRET}}";
    console.log("autofill detector running");
    
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
        if (!field || field.type === 'hidden' || field.type === 'submit' || field.type === 'button') {
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
        
        document.body.appendChild(btn);
        return btn;
    }
    
    // Position button relative to field (following password button pattern)
    function positionButton(btn, field) {
        const r = field.getBoundingClientRect();
        const emoji = btn.textContent;
        
        // Measure glyph size like password button does
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
        let side = Math.min(r.height, keyDim * 1.5);
        
        const topPosition = window.scrollY + r.top + (r.height - side) / 2;
        const leftPosition = window.scrollX + r.right - side - 5;
        
        btn.style.width = `${side}px`;
        btn.style.height = `${side}px`;
        btn.style.top = `${topPosition}px`;
        btn.style.left = `${leftPosition}px`;
        btn.style.display = 'flex';
    }
    
    // Show/hide button for field
    function updateFieldButton(field) {
        const fieldType = detectFieldType(field);
        
        if (fieldType && field.offsetParent !== null && !field.disabled && !field.readOnly) {
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
            if (fieldType && input.offsetParent !== null && !input.disabled && !input.readOnly) {
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
        
        console.log(`Found ${autofillableFields.length} autofillable fields`);
        
        // Show buttons on all autofillable fields
        showAllButtons();
    }
    
    // Run initial scan
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', scanForFields);
    } else {
        scanForFields();
    }
})();