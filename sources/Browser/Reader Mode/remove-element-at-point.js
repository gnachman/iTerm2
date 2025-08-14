// Remove element at specific point (what distraction removal mode would do)
(function() {
    'use strict';
    
    {{INCLUDE:distraction-removal-helpers.js}}
    
    const point = { x: {{POINT_X}}, y: {{POINT_Y}} };
    
    // Get the main container
    const mainContainer = detectMainContainer() || document.body;
    console.debug('[REMOVE] Main container:', 
        `${mainContainer.tagName}${mainContainer.id ? '#' + mainContainer.id : ''}${mainContainer.className ? '.' + mainContainer.className.split(' ').join('.') : ''}`);
    
    // Get elements at the point
    const elements = document.elementsFromPoint(point.x, point.y)
        .filter(x => x !== document.documentElement && x !== document.body);
    
    if (elements.length > 0) {
        const root = findRootOverlay(elements[0], mainContainer);
        console.debug('[REMOVE] Would remove:', 
            `${root.tagName}${root.id ? '#' + root.id : ''}${root.className ? '.' + root.className.split(' ').join('.') : ''}`);
    }
    
    // Inject styles and remove element (skip backdrop removal for targeted ad removal)
    injectDistractionRemovalStyles();
    const removed = [];
    removeElementAtPoint(point.x, point.y, mainContainer, removed, true);
    return true;
})();
