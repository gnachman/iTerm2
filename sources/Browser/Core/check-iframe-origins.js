// Check if page contains content from any origins (including all fetched resources and iframes)
(function() {
    function getAllOrigins() {
        const origins = new Set();
        
        // Add current frame origin
        try {
            origins.add(window.location.origin);
        } catch (e) {
            // Ignore cross-origin errors
        }
        
        // Check every fetched resource (images, scripts, stylesheets, XHR, etc.)
        try {
            const resources = performance.getEntriesByType('resource');
            for (const entry of resources) {
                try {
                    const url = new URL(entry.name);
                    origins.add(url.origin);
                } catch (e) {
                    // Skip invalid URLs
                }
            }
        } catch (e) {
            // Performance API might not be available
        }
        
        // Check all iframes
        const iframes = document.querySelectorAll('iframe');
        for (const iframe of iframes) {
            try {
                if (iframe.src) {
                    const url = new URL(iframe.src);
                    origins.add(url.origin);
                }
                
                // Try to access iframe content origin (will fail for cross-origin)
                try {
                    const frameOrigin = iframe.contentWindow.location.origin;
                    origins.add(frameOrigin);
                } catch (e) {
                    // Cross-origin iframe, use src URL instead
                }
            } catch (e) {
                // Skip iframes we can't access
            }
        }
        
        return Array.from(origins);
    }
    
    return getAllOrigins();
})();