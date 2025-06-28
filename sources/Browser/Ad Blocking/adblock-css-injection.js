(function() {
    'use strict';
    
    // Create style element for hiding ad elements
    var style = document.createElement('style');
    style.setAttribute('data-adblock', 'true');
    style.textContent = '{{CSS_CONTENT}}';
    
    // Inject into document head
    if (document.head) {
        document.head.appendChild(style);
    } else {
        // If head doesn't exist yet, wait for DOM ready
        document.addEventListener('DOMContentLoaded', function() {
            if (document.head) {
                document.head.appendChild(style);
            }
        });
    }
    return true;
})();
