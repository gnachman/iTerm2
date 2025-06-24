// Reader Mode functionality for iTerm2 Browser
(function() {
    'use strict';
    
    let isReaderMode = false;
    let originalContent = null;
    let readerContainer = null;
    
    // Create reader mode styles
    const readerStyles = `{{READER_MODE_CSS}}`;
    
    // Inject reader mode styles
    function injectStyles() {
        if (document.getElementById('iterm-reader-styles')) return;
        
        const style = document.createElement('style');
        style.id = 'iterm-reader-styles';
        style.textContent = readerStyles;
        document.head.appendChild(style);
    }
    
    // Toggle reader mode
    function toggleReaderMode() {
        if (isReaderMode) {
            exitReaderMode();
        } else {
            enterReaderMode();
        }
        return true;
    }
    
    // Enter reader mode
    function enterReaderMode() {
        if (typeof Readability === 'undefined') {
            return false;
        }
        
        try {
            // Clone the document to avoid modifying the original
            const documentClone = document.cloneNode(true);
            const reader = new Readability(documentClone);
            const article = reader.parse();
            
            if (!article || !article.content) {
                console.warn('Could not parse article content');
                return false;
            }
            
            // Inject styles
            injectStyles();
            
            // Create reader container
            readerContainer = document.createElement('div');
            readerContainer.className = 'iterm-reader-container';
            
            const readerContent = document.createElement('div');
            readerContent.className = 'iterm-reader-mode';
            
            // Set the reader content
            readerContent.innerHTML = `
                <h1>${article.title || 'Article'}</h1>
                ${article.content}
            `;
            
            readerContainer.appendChild(readerContent);
            document.body.appendChild(readerContainer);
            document.body.classList.add('reader-mode-active');
            
            isReaderMode = true;
            
            // Notify native code about reader mode state
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerMode) {
                window.webkit.messageHandlers.readerMode.postMessage({
                    action: 'entered',
                    title: article.title
                });
            }
            
            return true;
        } catch (error) {
            return false;
        }
    }
    
    // Exit reader mode
    function exitReaderMode() {
        if (readerContainer) {
            readerContainer.remove();
            readerContainer = null;
        }
        
        document.body.classList.remove('reader-mode-active');
        isReaderMode = false;
        
        // Notify native code about reader mode state
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerMode) {
            window.webkit.messageHandlers.readerMode.postMessage({
                action: 'exited'
            });
        }
        
        return true;
    }
    
    // Check if reader mode is available for current page
    function isReaderModeAvailable() {
        if (typeof Readability === 'undefined') {
            return false;
        }
        
        try {
            const documentClone = document.cloneNode(true);
            const reader = new Readability(documentClone);
            const article = reader.parse();
            
            return article && article.content && article.content.trim().length > 500;
        } catch (error) {
            return false;
        }
    }
    
    // Expose functions to global scope for native code to call
    window.iTermReaderMode = {
        toggle: toggleReaderMode,
        enter: enterReaderMode,
        exit: exitReaderMode,
        isActive: function() { return isReaderMode; },
        isAvailable: isReaderModeAvailable
    };
    
    // Handle escape key to exit reader mode
    document.addEventListener('keydown', function(event) {
        if (event.key === 'Escape' && isReaderMode) {
            exitReaderMode();
        }
    });
    
    return true;
})();