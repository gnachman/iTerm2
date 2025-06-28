// Visual debug version to see the DOM tree and what would be removed
(function() {
    'use strict';
    
    {{INCLUDE:distraction-removal-helpers.js}}
    
    const point = { x: {{POINT_X}}, y: {{POINT_Y}} };
    
    // Clean up any previous debug visuals
    document.querySelectorAll('.debug-border, .debug-label, .debug-click-dot').forEach(el => el.remove());
    
    // Add click dot
    const clickDot = document.createElement('div');
    clickDot.className = 'debug-click-dot';
    clickDot.style.cssText = `
        position: fixed;
        left: ${point.x - 5}px;
        top: ${point.y - 5}px;
        width: 10px;
        height: 10px;
        background: red;
        border-radius: 50%;
        z-index: 999999;
        pointer-events: none;
    `;
    document.body.appendChild(clickDot);
    
    console.log('[VISUAL DEBUG] Click point:', point);
    
    // Get elements at the point
    const elements = document.elementsFromPoint(point.x, point.y)
        .filter(x => x !== document.documentElement && x !== document.body);
    
    if (elements.length === 0) {
        console.log('[VISUAL DEBUG] No elements found at point');
        return;
    }
    
    const mainContainer = detectMainContainer() || document.body;
    console.log('[VISUAL DEBUG] Main container:', 
        `${mainContainer.tagName}${mainContainer.id ? '#' + mainContainer.id : ''}${mainContainer.className ? '.' + mainContainer.className.split(' ').join('.') : ''}`);
    
    // Add border to main container
    mainContainer.style.outline = '5px solid blue';
    const mainLabel = document.createElement('div');
    mainLabel.className = 'debug-label';
    mainLabel.textContent = 'MAIN CONTAINER: ' + mainContainer.tagName + (mainContainer.id ? '#' + mainContainer.id : '') + (mainContainer.className ? '.' + mainContainer.className.split(' ').join('.') : '');
    mainLabel.style.cssText = `
        position: absolute;
        background: white;
        color: black;
        border: 2px solid blue;
        padding: 2px 5px;
        font-size: 12px;
        font-family: monospace;
        z-index: 999998;
        pointer-events: none;
        top: -20px;
        left: 0;
    `;
    mainContainer.style.position = 'relative';
    mainContainer.appendChild(mainLabel);
    
    // Walk up the tree from clicked element
    const clickedElement = elements[0];
    let curr = clickedElement;
    let step = 0;
    const colors = ['#ff0000', '#ff8800', '#ffff00', '#88ff00', '#00ff00', '#00ff88', '#00ffff', '#0088ff', '#0000ff', '#8800ff'];
    
    console.log('[VISUAL DEBUG] Walking up DOM tree:');
    
    while (curr && curr !== mainContainer && curr !== document.body) {
        const color = colors[step % colors.length];
        const classes = curr.className || '';
        const id = curr.id || '';
        const combined = (classes + ' ' + id).toLowerCase();
        const isAdRelated = /(^|\s)(ad|advertisement|banner|popup|modal|overlay|sidebar|widget|promo)(\s|$)/.test(combined) ||
                           /(adsby|display_ad|ad_place|advert)/.test(combined);
        
        // Add border
        curr.style.outline = `3px solid ${color}`;
        curr.style.position = curr.style.position || 'relative';
        
        // Add label
        const label = document.createElement('div');
        label.className = 'debug-label';
        const elementName = `${curr.tagName}${curr.id ? '#' + curr.id : ''}${curr.className ? '.' + curr.className.split(' ').join('.') : ''}`;
        label.textContent = `${step}: ${elementName} ${isAdRelated ? '(AD-RELATED)' : ''}`;
        label.style.cssText = `
            position: absolute;
            background: white;
            color: black;
            border: 2px solid ${color};
            padding: 2px 5px;
            font-size: 11px;
            font-family: monospace;
            z-index: ${999990 - step};
            pointer-events: none;
            top: ${-18 - (step * 20)}px;
            left: 0;
            white-space: nowrap;
        `;
        curr.appendChild(label);
        
        console.log(`  ${step}: ${elementName} (ad-related: ${isAdRelated}, color: ${color})`);
        
        curr = curr.parentElement;
        step++;
    }
    
    // Show what would be removed
    const root = findRootOverlay(clickedElement, mainContainer);
    root.style.outline = '5px solid magenta';
    root.style.opacity = '0.5';
    root.style.position = root.style.position || 'relative';
    
    const removeLabel = document.createElement('div');
    removeLabel.className = 'debug-label';
    removeLabel.textContent = 'WOULD REMOVE: ' + root.tagName + (root.id ? '#' + root.id : '') + (root.className ? '.' + root.className.split(' ').join('.') : '');
    removeLabel.style.cssText = `
        position: absolute;
        background: white;
        color: black;
        border: 3px solid magenta;
        padding: 3px 8px;
        font-size: 14px;
        font-weight: bold;
        font-family: monospace;
        z-index: 999999;
        pointer-events: none;
        top: -25px;
        right: 0;
    `;
    root.appendChild(removeLabel);
    
    console.log('[VISUAL DEBUG] Would remove:', 
        `${root.tagName}${root.id ? '#' + root.id : ''}${root.className ? '.' + root.className.split(' ').join('.') : ''}`);
    
    // Visual debug will persist until page reload or next debug run
    
    return `Visual debug active. Check the page!`;
})();