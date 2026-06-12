(function() {
    var x = {{X}};
    var y = {{Y}};
    
    // Find the element at the clicked point
    var element = document.elementFromPoint(x, y);
    if (!element) return null;
    
    // Walk up the DOM tree to find a link
    var current = element;
    while (current && current !== document.body) {
        if (current.tagName === 'A' && current.href) {
            return {
                url: current.href,
                target: current.target || '_self'
            };
        }
        
        // Check if it's a clickable element with onclick or role="link"
        if (current.onclick || current.getAttribute('role') === 'link') {
            // Try to simulate a click and capture navigation
            var clickEvent = new MouseEvent('click', {
                view: window,
                bubbles: true,
                cancelable: true,
                clientX: x,
                clientY: y
            });
            
            // Store original window.open to intercept calls
            var originalOpen = window.open;
            var capturedUrl = null;
            window.open = function(url) {
                capturedUrl = url;
                return null; // Prevent actual opening
            };
            
            current.dispatchEvent(clickEvent);
            
            // Restore original window.open
            window.open = originalOpen;
            
            if (capturedUrl) {
                return {
                    url: capturedUrl,
                    target: '_blank'
                };
            }
        }
        
        current = current.parentElement;
    }
    
    return {};
})();
