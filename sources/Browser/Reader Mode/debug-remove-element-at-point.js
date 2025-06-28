// Debug version to understand what's happening with element removal
(function() {
    'use strict';
    
    {{INCLUDE:distraction-removal-helpers.js}}
    
    const point = { x: {{POINT_X}}, y: {{POINT_Y}} };
    
    console.log('[DEBUG] Starting element removal debug at point:', point);
    
    // Get elements at the point
    const elements = document.elementsFromPoint(point.x, point.y)
        .filter(x => x !== document.documentElement && x !== document.body);
    
    console.log('[DEBUG] Elements at point:');
    elements.forEach((el, i) => {
        console.log(`  ${i}: ${el.tagName}${el.id ? '#' + el.id : ''}${el.className ? '.' + el.className.split(' ').join('.') : ''}`);
        console.log(`     text: "${(el.innerText || '').substring(0, 50)}..."`);
    });
    
    // Test main container detection
    const mainContainer = detectMainContainer() || document.body;
    console.log('[DEBUG] Detected main container:', 
        `${mainContainer.tagName}${mainContainer.id ? '#' + mainContainer.id : ''}${mainContainer.className ? '.' + mainContainer.className.split(' ').join('.') : ''}`);
    console.log('[DEBUG] Main container text:', `"${(mainContainer.innerText || '').substring(0, 100)}..."`);
    
    // Test what would be removed
    if (elements.length > 0) {
        for (const el of elements) {
            if (el === mainContainer) {
                console.log('[DEBUG] Element is main container, would break');
                break;
            }
            
            const root = findRootOverlay(el, mainContainer);
            console.log('[DEBUG] Would remove root overlay:', 
                `${root.tagName}${root.id ? '#' + root.id : ''}${root.className ? '.' + root.className.split(' ').join('.') : ''}`);
            console.log('[DEBUG] Root overlay text:', `"${(root.innerText || '').substring(0, 100)}..."`);
            console.log('[DEBUG] Is main container?', root === mainContainer);
            console.log('[DEBUG] Contains main container?', root.contains(mainContainer));
            
            // Show the path from element to root with detailed analysis
            let curr = el;
            const path = [];
            console.log('[DEBUG] Walking up from clicked element:');
            let step = 0;
            while (curr && curr !== root && curr !== document.body) {
                const classes = curr.className || '';
                const id = curr.id || '';
                const combined = (classes + ' ' + id).toLowerCase();
                const isAdRelated = /(^|\s)(ad|advertisement|banner|popup|modal|overlay|sidebar|widget|promo)(\s|$)/.test(combined) ||
                                   /(adsby|display_ad|ad_place|advert)/.test(combined);
                
                console.log(`  ${step}: ${curr.tagName}${curr.id ? '#' + curr.id : ''}${curr.className ? '.' + curr.className.split(' ').join('.') : ''} (ad-related: ${isAdRelated})`);
                path.push(`${curr.tagName}${curr.id ? '#' + curr.id : ''}${curr.className ? '.' + curr.className.split(' ').join('.') : ''}`);
                curr = curr.parentElement;
                step++;
            }
            console.log('[DEBUG] Path from clicked element to root:', path.join(' -> '));
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
