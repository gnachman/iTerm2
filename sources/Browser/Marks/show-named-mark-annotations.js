(function() {
    // Remove any existing annotations
    var existingContainer = document.getElementById('iterm-mark-annotations');
    if (existingContainer) {
        existingContainer.remove();
    }
    
    var marks = {{MARKS_JSON}};
    if (!marks || marks.length === 0) {
        return false;
    }
    
    // Create container for annotations
    var container = document.createElement('div');
    container.id = 'iterm-mark-annotations';
    container.style.cssText = `
        position: absolute;
        top: 0;
        right: 0;
        width: 200px;
        height: 100%;
        pointer-events: none;
        z-index: 10000;
        padding: 20px 10px;
        box-sizing: border-box;
    `;
    
    marks.forEach(function(mark) {
        try {
            // Find the element using XPath
            var result = document.evaluate(
                mark.xpath,
                document,
                null,
                XPathResult.FIRST_ORDERED_NODE_TYPE,
                null
            );
            
            var element = result.singleNodeValue;
            if (!element) {
                console.log('Named mark element not found:', mark.name);
                return false;
            }
            
            // Calculate position in document
            var rect = element.getBoundingClientRect();
            var documentPosition = rect.top + window.pageYOffset + (mark.offsetY || 0);
            
            // Create annotation
            var annotation = document.createElement('div');
            annotation.className = 'iterm-mark-annotation';
            annotation.style.cssText = `
                position: absolute;
                right: 0;
                top: ${documentPosition}px;
                background: rgba(255, 215, 0, 0.9);
                color: #333;
                padding: 6px 12px 6px 20px;
                font-size: 12px;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                font-weight: 500;
                border-radius: 0 4px 4px 0;
                cursor: pointer;
                pointer-events: auto;
                min-width: 120px;
                max-width: 200px;
                word-wrap: break-word;
                transform: translateY(-50%);
                clip-path: polygon(15px 0%, 100% 0%, 100% 100%, 15px 100%, 0% 50%);
            `;
            annotation.textContent = mark.name;
            annotation.title = 'Click to hide annotation';
            
            // Add click handler to hide
            annotation.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                annotation.style.display = 'none';
            });
            
            container.appendChild(annotation);
            
        } catch (error) {
            console.log('Error creating annotation for mark:', mark.name, error);
        }
    });
    
    // Only add container if it has annotations
    if (container.children.length > 0) {
        document.body.appendChild(container);
    }
    return true;
})();
