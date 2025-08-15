// Core autofill field detection logic - shared between detector and fill-all

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

// Check if a text string indicates a login/username field
function isLoginRelatedText(text) {
    const lowerText = text.toLowerCase();
    return lowerText.includes('username') || 
           lowerText.includes('user_name') || 
           lowerText.includes('user-name') || 
           lowerText.includes('login') || 
           lowerText.includes('signin') || 
           lowerText.includes('sign in') || 
           lowerText.includes('email address');
}

// Detect field type
function detectFieldType(field) {
    if (!field || field.type === 'hidden' || field.type === 'submit' || field.type === 'button' || 
        field.type === 'checkbox' || field.type === 'radio' || field.type === 'password') {
        return null;
    }

    // Exclude iTerm mark annotation input fields
    if (field.closest('.iterm-mark-annotation') || field.closest('#iterm-mark-annotations')) {
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
        // Skip fullName detection if this looks like a login field
        if (type === 'fullName' && isLoginRelatedText(name)) {
            continue;
        }
        
        if (pattern.names?.some(n => name.includes(n))) {
            return type;
        }
    }
    
    // Check id attribute
    const id = field.id?.toLowerCase() || '';
    for (const [type, pattern] of Object.entries(fieldPatterns)) {
        // Skip fullName detection if this looks like a login field
        if (type === 'fullName' && isLoginRelatedText(id)) {
            continue;
        }
        
        if (pattern.ids?.some(i => id.includes(i))) {
            return type;
        }
    }
    
    // Check placeholder
    const placeholder = field.placeholder?.toLowerCase() || '';
    for (const [type, pattern] of Object.entries(fieldPatterns)) {
        // Skip fullName detection if this looks like a login field
        if (type === 'fullName' && isLoginRelatedText(placeholder)) {
            continue;
        }
        
        if (pattern.placeholders?.some(p => placeholder.includes(p))) {
            return type;
        }
    }
    
    // Check associated label
    const labels = getFieldLabels(field);
    for (const label of labels) {
        const labelText = label.textContent?.toLowerCase() || '';
        for (const [type, pattern] of Object.entries(fieldPatterns)) {
            // Skip fullName detection if this looks like a login field
            if (type === 'fullName' && isLoginRelatedText(labelText)) {
                continue;
            }
            
            if (pattern.labels?.some(l => labelText.includes(l))) {
                return type;
            }
        }
    }
    
    return null;
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
