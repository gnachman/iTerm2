(function() {
    'use strict';
    
    try {
        // Include core autofill detection logic
        {{INCLUDE:autofill-core.js}}
        
        const handlerName = 'iTermAutofillHandler';
        const sessionSecret = "{{SECRET}}";
        
        // Domain validation - prevent autofill on potentially malicious schemes
        const currentProtocol = window.location.protocol.toLowerCase();
        const currentHostname = window.location.hostname.toLowerCase();
        
        // Block dangerous protocols but allow standard web protocols and iTerm2's custom schemes
        const blockedProtocols = ['javascript:', 'data:', 'vbscript:'];
        if (blockedProtocols.some(blocked => currentProtocol.startsWith(blocked))) {
            return { success: false, error: "Autofill not permitted on this protocol" };
        }
        
        // For file:// protocol, only allow if hostname is empty (local files)
        if (currentProtocol === 'file:' && currentHostname !== '') {
            return { success: false, error: "Autofill not permitted on remote file URLs" };
        }
        
        // Verify the autofill detector is loaded
        if (!window.iTermAutofillDetectorLoaded) {
            return { success: false, error: "Autofill detector not loaded" };
        }
        
        // Find all autofillable fields using the same logic as the detector
        const inputs = document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="password"]), select');
        
        const autofillableFields = [];
        
        inputs.forEach((input) => {
            try {
                const fieldType = detectFieldType(input);
                const isInteractable = isFieldInteractable(input);
                
                if (fieldType && isInteractable) {
                    autofillableFields.push({
                        type: fieldType,
                        name: input.name || null,
                        id: input.id || null,
                        value: input.value || ''
                    });
                }
            } catch (fieldError) {
                // Silently continue processing other fields
            }
        });
        
        if (autofillableFields.length === 0) {
            return { success: true, fieldsFound: 0 };
        }
        
        // Send autofill request with all fields
        try {
            window.webkit.messageHandlers[handlerName].postMessage({
                type: 'autofillRequest',
                sessionSecret: sessionSecret,
                activeField: autofillableFields[0], // Use first field as "active"
                fields: autofillableFields
            });
            
            return { success: true, fieldsFound: autofillableFields.length };
        } catch (messageError) {
            return { success: false, error: "Failed to send autofill request" };
        }
        
    } catch (error) {
        return { success: false, error: "Autofill execution failed" };
    }
})();