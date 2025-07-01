(function() {
    // Include shared XPath utilities
    {{INCLUDE:xpath-utils.js}}
    
    // Include text fragment extraction utilities
    {{INCLUDE:extract-text-fragment.js}}
    
    // Get viewport center coordinates
    var centerX = window.innerWidth / 2;
    var centerY = window.innerHeight / 2;
    
    // Find the best element by scanning around the center point
    var element = findBestElementAroundCenter(centerX, centerY);
    if (!element) return null;
    
    // Calculate vertical offset from the top of the element to the viewport center
    var rect = element.getBoundingClientRect();
    var offsetY = centerY - rect.top;
    
    // Highlight the captured element briefly to show what was saved
    highlightElement(element);
    
    // Return element data with text fragment using enhanced utility
    return getTextFragmentData(element, offsetY);
    
    // Function to find the best element around the center point
    function findBestElementAroundCenter(centerX, centerY) {
        var candidates = [];
        
        // First try horizontal scanning (most important for viewport center)
        var searchRadius = 200; // Wider search for viewport center
        var stepSize = 25;
        
        // Scan horizontally
        for (var x = Math.max(0, centerX - searchRadius); x <= Math.min(window.innerWidth, centerX + searchRadius); x += stepSize) {
            var element = document.elementFromPoint(x, centerY);
            if (element && !isElementInCandidates(element, candidates)) {
                var score = scoreElementForViewport(element, centerX, centerY);
                if (score > 0) {
                    candidates.push({
                        element: element,
                        score: score,
                        distance: Math.abs(x - centerX)
                    });
                }
            }
        }
        
        // Also try radial search if we don't have good candidates
        if (candidates.length < 3) {
            var searchRadii = [0, 30, 60, 100];
            
            for (var i = 0; i < searchRadii.length; i++) {
                var radius = searchRadii[i];
                var offsets = [];
                
                if (radius === 0) {
                    offsets = [{x: 0, y: 0}];
                } else {
                    var numPoints = 8;
                    for (var j = 0; j < numPoints; j++) {
                        var angle = (j * 2 * Math.PI) / numPoints;
                        offsets.push({
                            x: Math.round(radius * Math.cos(angle)),
                            y: Math.round(radius * Math.sin(angle))
                        });
                    }
                }
                
                for (var k = 0; k < offsets.length; k++) {
                    var testX = centerX + offsets[k].x;
                    var testY = centerY + offsets[k].y;
                    
                    if (testX >= 0 && testX < window.innerWidth && 
                        testY >= 0 && testY < window.innerHeight) {
                        
                        var element = document.elementFromPoint(testX, testY);
                        if (element && !isElementInCandidates(element, candidates)) {
                            var score = scoreElementForViewport(element, centerX, centerY);
                            if (score > 0) {
                                candidates.push({
                                    element: element,
                                    score: score,
                                    distance: Math.sqrt(Math.pow(testX - centerX, 2) + Math.pow(testY - centerY, 2))
                                });
                            }
                        }
                    }
                }
            }
        }
        
        // Sort candidates by score (descending) and then by distance (ascending)
        candidates.sort(function(a, b) {
            if (a.score !== b.score) {
                return b.score - a.score;
            }
            return a.distance - b.distance;
        });
        
        // Fallback to any element at center if no good candidates found
        if (candidates.length === 0) {
            var fallback = document.elementFromPoint(centerX, centerY);
            if (fallback) {
                return fallback;
            }
        }
        
        return candidates.length > 0 ? candidates[0].element : null;
    }
    
    // Function to check if element is already in candidates list
    function isElementInCandidates(element, candidates) {
        return candidates.some(function(candidate) {
            return candidate.element === element;
        });
    }
    
    // Function to score an element for viewport center marking
    function scoreElementForViewport(element, centerX, centerY) {
        var score = 0;
        var rect = element.getBoundingClientRect();
        
        // Skip elements that are too large
        if (rect.height > window.innerHeight * 0.4) {
            return 0;
        }
        
        if (rect.width > window.innerWidth * 0.9) {
            return 0;
        }
        
        var tagName = element.tagName.toLowerCase();
        
        // Prefer content elements
        if (['p', 'span', 'div', 'article', 'section', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'td', 'th'].includes(tagName)) {
            score += 10;
        }
        
        // Boost for elements with meaningful text content
        var textContent = getCleanTextContent(element);
        if (textContent && textContent.length > 20) {
            score += 20;
            
            if (textContent.length > 50) {
                score += 10;
            }
            
            // Check for unique text
            var textFragment = createTextFragment(textContent);
            if (textFragment && isTextFragmentUniqueForViewport(textFragment)) {
                score += 15;
            }
        }
        
        // Prefer elements that are vertically close to center
        var verticalDistance = Math.abs((rect.top + rect.bottom) / 2 - centerY);
        if (verticalDistance < 50) {
            score += 10;
        }
        
        // Boost for meaningful elements
        if (isMeaningfulElement(element)) {
            score += 5;
        }
        
        return Math.max(0, score);
    }
    
    // Function to check if text fragment is unique (simpler version for viewport)
    function isTextFragmentUniqueForViewport(textFragment) {
        if (!textFragment || textFragment.length < 10) return false;
        
        var bodyText = document.body.textContent || '';
        var occurrences = (bodyText.toLowerCase().match(new RegExp(textFragment.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g')) || []).length;
        
        return occurrences === 1;
    }
})();