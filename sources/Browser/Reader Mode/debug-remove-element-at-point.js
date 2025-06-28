// Debug version to understand what's happening with element removal
(function() {
    'use strict';
    
    {{INCLUDE:distraction-removal-helpers.js}}
    
    const point = { x: {{POINT_X}}, y: {{POINT_Y}} };
    
    console.log('[DEBUG] Starting element removal debug at point:', point);
    
    // Get elements at the point
    const elements = document.elementsFromPoint(point.x, point.y)
        .filter(x => x !== document.documentElement && x !== document.body);
    
    console.log('[DEBUG] Elements at point:', elements.map(el => ({
        tag: el.tagName,
        id: el.id,
        classes: el.className,
        text: el.innerText?.substring(0, 50) + '...'
    })));
    
    // Test main container detection
    const mainContainer = detectMainContainer() || document.body;
    console.log('[DEBUG] Detected main container:', {
        tag: mainContainer.tagName,
        id: mainContainer.id,
        classes: mainContainer.className,
        text: mainContainer.innerText?.substring(0, 100) + '...'
    });
    
    // Test what would be removed
    if (elements.length > 0) {
        for (const el of elements) {
            if (el === mainContainer) {
                console.log('[DEBUG] Element is main container, would break');
                break;
            }
            
            const root = findRootOverlay(el, mainContainer);
            console.log('[DEBUG] Would remove root overlay:', {
                tag: root.tagName,
                id: root.id,
                classes: root.className,
                text: root.innerText?.substring(0, 100) + '...',
                isMainContainer: root === mainContainer,
                containsMainContainer: root.contains(mainContainer)
            });
            
            // Show the path from element to root
            let curr = el;
            const path = [];
            while (curr && curr !== root && curr !== document.body) {
                path.push({
                    tag: curr.tagName,
                    id: curr.id,
                    classes: curr.className
                });
                curr = curr.parentElement;
            }
            console.log('[DEBUG] Path from clicked element to root:', path);
            break;
        }
    }
    
    return {
        point,
        elements: elements.length,
        mainContainer: mainContainer.tagName + (mainContainer.id ? '#' + mainContainer.id : ''),
        wouldRemove: elements.length > 0 ? findRootOverlay(elements[0], mainContainer).tagName + (findRootOverlay(elements[0], mainContainer).id ? '#' + findRootOverlay(elements[0], mainContainer).id : '') : 'nothing'
    };
})();