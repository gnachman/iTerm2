(function() {
    var x = {{X}};
    var y = {{Y}};
    var urls = [];
    
    // Find the element at the clicked point
    var element = document.elementFromPoint(x, y);
    if (!element) return urls;
    
    // Check if it's an image
    if (element.tagName === 'IMG' && element.src) {
        urls.push(element.src);
    }
    
    // Check if it's a video
    if (element.tagName === 'VIDEO' && element.src) {
        urls.push(element.src);
    }
    
    // Check if it's an audio element
    if (element.tagName === 'AUDIO' && element.src) {
        urls.push(element.src);
    }
    
    // Check for background images
    var bgImage = window.getComputedStyle(element).backgroundImage;
    if (bgImage && bgImage !== 'none') {
        var match = bgImage.match(/url\(['"]?([^'"]+)['"]?\)/);
        if (match && match[1]) {
            var bgUrl = match[1];
            // Convert relative URLs to absolute
            if (bgUrl.indexOf('://') === -1) {
                var a = document.createElement('a');
                a.href = bgUrl;
                bgUrl = a.href;
            }
            if (urls.indexOf(bgUrl) === -1) {
                urls.push(bgUrl);
            }
        }
    }
    
    // Check for source elements (for picture/video/audio with multiple sources)
    var sources = element.querySelectorAll('source');
    sources.forEach(function(source) {
        if (source.src && urls.indexOf(source.src) === -1) {
            urls.push(source.src);
        }
    });
    
    return urls;
})();