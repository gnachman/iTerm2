(function() {
    if (typeof Readability === 'undefined') {
        return null;
    }
    
    try {
        // Clone the document to avoid modifying the original
        const documentClone = document.cloneNode(true);
        const reader = new Readability(documentClone);
        const article = reader.parse();
        
        if (!article || !article.content) {
            return null;
        }
        
        // Create a temporary div to extract plain text from HTML
        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = article.content;
        
        // Extract plain text, preserving some structure
        const textContent = tempDiv.textContent || tempDiv.innerText || '';
        
        // Clean up extra whitespace and return
        return textContent.replace(/\s+/g, ' ').trim();
    } catch (error) {
        return "";
    }
})()
