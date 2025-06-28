// Remove element at specific point (what distraction removal mode would do)
(function() {
    'use strict';
    
    {{INCLUDE:distraction-removal-helpers.js}}
    
    const point = { x: {{POINT_X}}, y: {{POINT_Y}} };
    
    // Get the main container
    const mainContainer = detectMainContainer() || document.body;
    
    // Inject styles and remove element
    injectDistractionRemovalStyles();
    const removed = [];
    removeElementAtPoint(point.x, point.y, mainContainer, removed);
    return true;
})();
