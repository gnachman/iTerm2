// Recursively extract all resource URLs from the current page and all accessible iframes
(function() {
    const urls = new Set();
    const processedIframes = new Set(); // Prevent infinite loops
    
    // Helper function to convert to absolute URL
    function toAbsoluteURL(url, baseURL = window.location.href) {
        try {
            return new URL(url, baseURL).href;
        } catch (e) {
            return null;
        }
    }
    
    // Recursive function to extract resources from a document
    function extractResourcesFromDocument(doc, baseURL = window.location.href) {
        try {
            // Images
            doc.querySelectorAll('img[src]').forEach(img => {
                if (img.src && !img.src.startsWith('data:')) {
                    const absoluteURL = toAbsoluteURL(img.src, baseURL);
                    if (absoluteURL) urls.add(absoluteURL);
                }
            });
            
            // CSS files
            doc.querySelectorAll('link[rel="stylesheet"][href]').forEach(link => {
                if (link.href && !link.href.startsWith('data:')) {
                    const absoluteURL = toAbsoluteURL(link.href, baseURL);
                    if (absoluteURL) urls.add(absoluteURL);
                }
            });
            
            // JavaScript files
            doc.querySelectorAll('script[src]').forEach(script => {
                if (script.src && !script.src.startsWith('data:')) {
                    const absoluteURL = toAbsoluteURL(script.src, baseURL);
                    if (absoluteURL) urls.add(absoluteURL);
                }
            });
            
            // Background images in style attributes
            doc.querySelectorAll('[style*="background"]').forEach(el => {
                const style = el.style?.cssText || el.getAttribute('style') || '';
                const urlMatches = style.match(/url\s*\(\s*["']?([^"')]+)["']?\s*\)/gi);
                if (urlMatches) {
                    urlMatches.forEach(match => {
                        const url = match.replace(/url\s*\(\s*["']?/, '').replace(/["']?\s*\)/, '');
                        if (!url.startsWith('data:')) {
                            const absoluteURL = toAbsoluteURL(url, baseURL);
                            if (absoluteURL) urls.add(absoluteURL);
                        }
                    });
                }
            });
            
            // CSS @import and url() in <style> tags
            doc.querySelectorAll('style').forEach(style => {
                const cssText = style.textContent || '';
                
                // Handle url() in CSS
                const urlMatches = cssText.match(/url\s*\(\s*["']?([^"')]+)["']?\s*\)/gi);
                if (urlMatches) {
                    urlMatches.forEach(match => {
                        const url = match.replace(/url\s*\(\s*["']?/, '').replace(/["']?\s*\)/, '');
                        if (!url.startsWith('data:')) {
                            const absoluteURL = toAbsoluteURL(url, baseURL);
                            if (absoluteURL) urls.add(absoluteURL);
                        }
                    });
                }
                
                // Handle @import statements
                const importMatches = cssText.match(/@import\s+["']([^"']+)["']/gi);
                if (importMatches) {
                    importMatches.forEach(match => {
                        const url = match.replace(/@import\s+["']/, '').replace(/["']/, '');
                        const absoluteURL = toAbsoluteURL(url, baseURL);
                        if (absoluteURL) urls.add(absoluteURL);
                    });
                }
            });
            
            // Favicon and other link elements
            doc.querySelectorAll('link[href]:not([rel="stylesheet"])').forEach(link => {
                if (link.href && !link.href.startsWith('data:') && !link.href.startsWith('mailto:')) {
                    try {
                        const absoluteURL = toAbsoluteURL(link.href, baseURL);
                        if (absoluteURL) {
                            const linkURL = new URL(absoluteURL);
                            const currentOrigin = new URL(baseURL).origin;
                            if (linkURL.origin === currentOrigin || 
                                ['icon', 'shortcut icon', 'apple-touch-icon', 'manifest'].includes(link.rel)) {
                                urls.add(absoluteURL);
                            }
                        }
                    } catch (e) {
                        // Invalid URL, skip
                    }
                }
            });
            
            // Video and audio sources
            doc.querySelectorAll('video[src], audio[src]').forEach(media => {
                if (media.src && !media.src.startsWith('data:')) {
                    const absoluteURL = toAbsoluteURL(media.src, baseURL);
                    if (absoluteURL) urls.add(absoluteURL);
                }
            });
            
            // Video and audio source elements
            doc.querySelectorAll('video source[src], audio source[src]').forEach(source => {
                if (source.src && !source.src.startsWith('data:')) {
                    const absoluteURL = toAbsoluteURL(source.src, baseURL);
                    if (absoluteURL) urls.add(absoluteURL);
                }
            });
            
            // Object and embed elements
            doc.querySelectorAll('object[data], embed[src]').forEach(el => {
                const src = el.getAttribute('data') || el.getAttribute('src');
                if (src && !src.startsWith('data:')) {
                    const absoluteURL = toAbsoluteURL(src, baseURL);
                    if (absoluteURL) urls.add(absoluteURL);
                }
            });
            
            // Process iframes recursively
            doc.querySelectorAll('iframe').forEach(iframe => {
                // First, add the iframe src itself as a resource
                if (iframe.src && !iframe.src.startsWith('data:') && !iframe.src.startsWith('javascript:')) {
                    const absoluteURL = toAbsoluteURL(iframe.src, baseURL);
                    if (absoluteURL) {
                        urls.add(absoluteURL);
                        
                        // Prevent processing the same iframe multiple times
                        if (!processedIframes.has(absoluteURL)) {
                            processedIframes.add(absoluteURL);
                            
                            // Try to access iframe content for same-origin iframes
                            try {
                                const iframeDoc = iframe.contentDocument || iframe.contentWindow?.document;
                                if (iframeDoc) {
                                    // Use the iframe's location as the new base URL
                                    const iframeBaseURL = iframe.contentWindow.location.href;
                                    extractResourcesFromDocument(iframeDoc, iframeBaseURL);
                                }
                            } catch (e) {
                                // Cross-origin iframe, can't access content
                                // This is expected and normal for many iframes
                                console.debug('Cannot access iframe content (cross-origin):', iframe.src);
                            }
                        }
                    }
                }
            });
            
        } catch (e) {
            console.error('Error extracting resources from document:', e);
        }
    }
    
    // Start extraction from the main document
    extractResourcesFromDocument(document, window.location.href);
    
    return Array.from(urls);
})();
