// Recursively rewrite resource URLs in the DOM and all accessible iframes
// URL_MAPPING_PLACEHOLDER will be replaced with actual mapping data
(function() {
    const urlMapping = new Map(URL_MAPPING_PLACEHOLDER);
    const processedIframes = new Set(); // Prevent infinite loops
    
    // Recursive function to rewrite URLs in a document
    function rewriteResourcesInDocument(doc) {
        try {
            // Update image sources
            doc.querySelectorAll('img[src]').forEach(img => {
                if (urlMapping.has(img.src)) {
                    img.src = urlMapping.get(img.src);
                }
            });
            
            // Update stylesheet hrefs
            doc.querySelectorAll('link[rel="stylesheet"][href]').forEach(link => {
                if (urlMapping.has(link.href)) {
                    link.href = urlMapping.get(link.href);
                }
            });
            
            // Update script sources
            doc.querySelectorAll('script[src]').forEach(script => {
                if (urlMapping.has(script.src)) {
                    script.src = urlMapping.get(script.src);
                }
            });
            
            // Update background images in style attributes
            doc.querySelectorAll('[style*="background"]').forEach(el => {
                let style = el.getAttribute('style') || '';
                urlMapping.forEach((localPath, originalURL) => {
                    const escapedURL = originalURL.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                    const urlPattern = new RegExp('url\\s*\\(\\s*["\']?' + escapedURL + '["\']?\\s*\\)', 'gi');
                    style = style.replace(urlPattern, `url('${localPath}')`);
                });
                if (style !== el.getAttribute('style')) {
                    el.setAttribute('style', style);
                }
            });
            
            // Update CSS in <style> tags
            doc.querySelectorAll('style').forEach(styleEl => {
                let cssText = styleEl.textContent || '';
                urlMapping.forEach((localPath, originalURL) => {
                    const escapedURL = originalURL.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                    const urlPattern = new RegExp('url\\s*\\(\\s*["\']?' + escapedURL + '["\']?\\s*\\)', 'gi');
                    cssText = cssText.replace(urlPattern, `url('${localPath}')`);
                    
                    const importPattern = new RegExp('@import\\s+["\']' + escapedURL + '["\']', 'gi');
                    cssText = cssText.replace(importPattern, `@import '${localPath}'`);
                });
                if (cssText !== styleEl.textContent) {
                    styleEl.textContent = cssText;
                }
            });
            
            // Update other link hrefs (favicons, manifests, etc.)
            doc.querySelectorAll('link[href]:not([rel="stylesheet"])').forEach(link => {
                if (urlMapping.has(link.href)) {
                    link.href = urlMapping.get(link.href);
                }
            });
            
            // Update video and audio sources
            doc.querySelectorAll('video[src], audio[src]').forEach(media => {
                if (urlMapping.has(media.src)) {
                    media.src = urlMapping.get(media.src);
                }
            });
            
            // Update video and audio source elements
            doc.querySelectorAll('video source[src], audio source[src]').forEach(source => {
                if (urlMapping.has(source.src)) {
                    source.src = urlMapping.get(source.src);
                }
            });
            
            // Update object and embed elements
            doc.querySelectorAll('object[data]').forEach(obj => {
                if (urlMapping.has(obj.data)) {
                    obj.data = urlMapping.get(obj.data);
                }
            });
            
            doc.querySelectorAll('embed[src]').forEach(embed => {
                if (urlMapping.has(embed.src)) {
                    embed.src = urlMapping.get(embed.src);
                }
            });
            
            // Process iframes recursively
            doc.querySelectorAll('iframe').forEach(iframe => {
                // Update iframe src if it's in our mapping
                if (iframe.src && urlMapping.has(iframe.src)) {
                    iframe.src = urlMapping.get(iframe.src);
                }
                
                // Try to process iframe content for same-origin iframes
                try {
                    const iframeDoc = iframe.contentDocument || iframe.contentWindow?.document;
                    if (iframeDoc) {
                        const iframeURL = iframe.contentWindow.location.href;
                        
                        // Prevent processing the same iframe multiple times
                        if (!processedIframes.has(iframeURL)) {
                            processedIframes.add(iframeURL);
                            rewriteResourcesInDocument(iframeDoc);
                        }
                    }
                } catch (e) {
                    // Cross-origin iframe, can't access content
                    // This is expected and normal for many iframes
                    console.debug('Cannot access iframe content for rewriting (cross-origin):', iframe.src);
                }
            });
            
        } catch (e) {
            console.error('Error rewriting resources in document:', e);
        }
    }
    
    // Start rewriting from the main document
    rewriteResourcesInDocument(document);
    
    return document.documentElement.outerHTML;
})();
