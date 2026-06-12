// Add data-saved-* attributes with rewritten URLs without modifying the original page
// URL_MAPPING_PLACEHOLDER will be replaced with actual mapping data
(function() {
    const urlMapping = new Map(URL_MAPPING_PLACEHOLDER);
    const processedIframes = new Set(); // Prevent infinite loops
    
    // Recursive function to add saved attributes in a document
    function addSavedAttributesInDocument(doc) {
        try {
            // Add data-saved-src for images
            doc.querySelectorAll('img[src]').forEach(img => {
                if (urlMapping.has(img.src)) {
                    img.setAttribute('data-saved-src', urlMapping.get(img.src));
                }
            });
            
            // Add data-saved-css-content for stylesheet links
            doc.querySelectorAll('link[rel="stylesheet"][href]').forEach(link => {
                if (urlMapping.has(link.href)) {
                    link.setAttribute('data-saved-css-content', urlMapping.get(link.href));
                }
            });
            
            // Add data-saved-src for scripts
            doc.querySelectorAll('script[src]').forEach(script => {
                if (urlMapping.has(script.src)) {
                    script.setAttribute('data-saved-src', urlMapping.get(script.src));
                }
            });
            
            // Add data-saved-style for background images in style attributes
            doc.querySelectorAll('[style*="background"]').forEach(el => {
                let style = el.getAttribute('style') || '';
                let savedStyle = style;
                urlMapping.forEach((localPath, originalURL) => {
                    const escapedURL = originalURL.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                    const urlPattern = new RegExp('url\\s*\\(\\s*["\']?' + escapedURL + '["\']?\\s*\\)', 'gi');
                    savedStyle = savedStyle.replace(urlPattern, `url('${localPath}')`);
                });
                if (savedStyle !== style) {
                    el.setAttribute('data-saved-style', savedStyle);
                }
            });
            
            // Add data-saved-content for CSS in <style> tags
            doc.querySelectorAll('style').forEach(styleEl => {
                let cssText = styleEl.textContent || '';
                let savedCssText = cssText;
                urlMapping.forEach((localPath, originalURL) => {
                    const escapedURL = originalURL.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                    const urlPattern = new RegExp('url\\s*\\(\\s*["\']?' + escapedURL + '["\']?\\s*\\)', 'gi');
                    savedCssText = savedCssText.replace(urlPattern, `url('${localPath}')`);
                    
                    const importPattern = new RegExp('@import\\s+["\']' + escapedURL + '["\']', 'gi');
                    savedCssText = savedCssText.replace(importPattern, `@import '${localPath}'`);
                });
                if (savedCssText !== cssText) {
                    styleEl.setAttribute('data-saved-content', savedCssText);
                }
            });
            
            // Add data-saved-href for other link hrefs (favicons, manifests, etc.)
            doc.querySelectorAll('link[href]:not([rel="stylesheet"])').forEach(link => {
                if (urlMapping.has(link.href)) {
                    link.setAttribute('data-saved-href', urlMapping.get(link.href));
                }
            });
            
            // Add data-saved-src for video and audio sources
            doc.querySelectorAll('video[src], audio[src]').forEach(media => {
                if (urlMapping.has(media.src)) {
                    media.setAttribute('data-saved-src', urlMapping.get(media.src));
                }
            });
            
            // Add data-saved-src for video and audio source elements
            doc.querySelectorAll('video source[src], audio source[src]').forEach(source => {
                if (urlMapping.has(source.src)) {
                    source.setAttribute('data-saved-src', urlMapping.get(source.src));
                }
            });
            
            // Add data-saved-data for object elements
            doc.querySelectorAll('object[data]').forEach(obj => {
                if (urlMapping.has(obj.data)) {
                    obj.setAttribute('data-saved-data', urlMapping.get(obj.data));
                }
            });
            
            // Add data-saved-src for embed elements
            doc.querySelectorAll('embed[src]').forEach(embed => {
                if (urlMapping.has(embed.src)) {
                    embed.setAttribute('data-saved-src', urlMapping.get(embed.src));
                }
            });
            
            // Process iframes recursively
            doc.querySelectorAll('iframe').forEach(iframe => {
                // Add data-saved-src for iframe src if it's in our mapping
                if (iframe.src && urlMapping.has(iframe.src)) {
                    iframe.setAttribute('data-saved-src', urlMapping.get(iframe.src));
                }
                
                // Try to process iframe content for same-origin iframes
                try {
                    const iframeDoc = iframe.contentDocument || iframe.contentWindow?.document;
                    if (iframeDoc) {
                        const iframeURL = iframe.contentWindow.location.href;
                        
                        // Prevent processing the same iframe multiple times
                        if (!processedIframes.has(iframeURL)) {
                            processedIframes.add(iframeURL);
                            addSavedAttributesInDocument(iframeDoc);
                        }
                    }
                } catch (e) {
                    // Cross-origin iframe, can't access content
                    // This is expected and normal for many iframes
                    console.debug('Cannot access iframe content for adding saved attributes (cross-origin):', iframe.src);
                }
            });
            
        } catch (e) {
            console.error('Error adding saved attributes in document:', e);
        }
    }
    
    // Start adding saved attributes from the main document
    addSavedAttributesInDocument(document);
    
    return 'Saved attributes added successfully';
})();
