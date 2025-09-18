(function() {
    // Include text fragment extraction utilities
    {{INCLUDE:extract-text-fragment.js}}

    // Parameters passed via template substitution
    var clickX = parseInt("{{CLICK_X}}") || 0;
    var clickY = parseInt("{{CLICK_Y}}") || 0;

    console.debug('get-xpath-at-point.js: Getting XPath at point:', clickX, clickY);

    // Find the best element by scanning horizontally around the click point
    var bestElement = findBestElementHorizontally(clickX, clickY);
    if (!bestElement) {
        console.debug('get-xpath-at-point.js: No suitable element found with scanning, falling back to direct element');
        // Fallback to element directly at click point
        bestElement = document.elementFromPoint(clickX, clickY);
        if (!bestElement) {
            console.debug('get-xpath-at-point.js: No element found at all');
            return null;
        }
    }

    console.debug('get-xpath-at-point.js: Found best element:', bestElement);

    // Calculate vertical offset from the top of the element to the click point
    var rect = bestElement.getBoundingClientRect();
    var offsetY = clickY - rect.top;

    // Highlight the captured element briefly to show what was saved
    highlightElement(bestElement);

    console.debug('get-xpath-at-point.js: Generated XPath for element');

    // Return element data with text fragment using enhanced utility
    let result = getTextFragmentData(bestElement, offsetY, clickY);
    console.debug(`get-xpath-at-point returning ${result}`);
    return result;

    // Function to find the best element by scanning horizontally
    function findBestElementHorizontally(centerX, centerY) {
        var candidates = [];
        var stepSize = 30; // Pixel steps for scanning

        console.debug('get-xpath-at-point.js: Starting horizontal scan across full page width from 0 to', window.innerWidth);

        // Scan horizontally across the entire page width
        for (var x = 0; x < window.innerWidth; x += stepSize) {
            var element = document.elementFromPoint(x, centerY);
            if (element) {
                console.debug('get-xpath-at-point.js: Found element at x=' + x + ':', element.tagName);
                if (!isElementInCandidates(element, candidates)) {
                    var score = scoreElement(element, centerX, centerY);
                    console.debug('get-xpath-at-point.js: Element score:', score);
                    if (score > 0) {
                        candidates.push({
                            element: element,
                            score: score,
                            distance: Math.abs(x - centerX)
                        });
                        console.debug('get-xpath-at-point.js: Added candidate with score', score);
                    }
                } else {
                    console.debug('get-xpath-at-point.js: Element already in candidates');
                }
            } else {
                console.debug('get-xpath-at-point.js: No element found at x=' + x);
            }
        }

        // Sort candidates by score (descending) and then by distance (ascending)
        candidates.sort(function(a, b) {
            if (a.score !== b.score) {
                return b.score - a.score; // Higher score first
            }
            return a.distance - b.distance; // Closer distance first if scores are equal
        });

        console.debug('get-xpath-at-point.js: Found', candidates.length, 'candidates');
        candidates.forEach(function(candidate, index) {
            console.debug('  Candidate', index + 1, ':', candidate.element.tagName, 'score:', candidate.score, 'distance:', candidate.distance);
        });

        return candidates.length > 0 ? candidates[0].element : null;
    }

    // Function to check if element is already in candidates list
    function isElementInCandidates(element, candidates) {
        return candidates.some(function(candidate) {
            return candidate.element === element;
        });
    }

    // Function to score an element based on suitability for marking
    function scoreElement(element, centerX, centerY) {
        var score = 1; // Start with base score so all elements have some value
        var rect = element.getBoundingClientRect();

        console.debug('get-xpath-at-point.js: Scoring element:', element.tagName, 'rect:', rect.width + 'x' + rect.height);

        // Skip elements that don't contain the click point vertically (but be more lenient)
        if (centerY < rect.top - 5 || centerY > rect.bottom + 5) {
            console.debug('get-xpath-at-point.js: Element does not contain click point vertically');
            return 0;
        }

        // Heavily penalize extremely large elements but don't exclude them completely
        if (rect.height > window.innerHeight * 0.8) {
            score -= 50; // Heavy penalty for very tall elements
        } else if (rect.height > window.innerHeight * 0.5) {
            score -= 20; // Moderate penalty for tall elements
        }

        if (rect.width > window.innerWidth * 0.95) {
            score -= 30; // Penalty for very wide elements
        }

        var tagName = element.tagName.toLowerCase();

        // Prefer content elements
        if (['p', 'span', 'div', 'article', 'section', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'td', 'th'].includes(tagName)) {
            score += 15;
        } else if (['a', 'button', 'input'].includes(tagName)) {
            score += 5; // Some boost for interactive elements
        }

        // Boost for elements with meaningful text content
        var textContent = getCleanTextContent(element);
        if (textContent && textContent.length > 10) { // Lowered threshold
            score += 20;

            // Extra boost for substantial text content
            if (textContent.length > 30) { // Lowered threshold
                score += 15;
            }

            if (textContent.length > 100) {
                score += 10;
            }

            // Check if text appears unique on the page
            var textFragment = createTextFragment(textContent);
            if (textFragment && isTextFragmentUnique(textFragment)) {
                score += 25; // Big boost for unique text
            }
        } else if (textContent && textContent.length > 0) {
            score += 5; // Small boost for any text
        }

        // Prefer smaller elements (more specific positioning)
        var area = rect.width * rect.height;
        var viewportArea = window.innerWidth * window.innerHeight;
        var areaRatio = area / viewportArea;

        if (areaRatio < 0.05) { // Small elements
            score += 15;
        } else if (areaRatio < 0.1) { // Medium elements
            score += 10;
        } else if (areaRatio < 0.2) { // Larger elements
            score += 5;
        }

        // Boost for elements with IDs or meaningful classes
        if (element.id) {
            score += 10;
        }

        if (element.className && typeof element.className === 'string') {
            var className = element.className.toLowerCase();
            if (className.includes('content') || className.includes('text') ||
                className.includes('article') || className.includes('paragraph')) {
                score += 12;
            }
        }

        // Heavily penalize navigation and structural elements
        if (['nav', 'header', 'footer', 'aside'].includes(tagName)) {
            score -= 30;
        }

        if (element.className && typeof element.className === 'string') {
            var className = element.className.toLowerCase();
            if (className.includes('nav') || className.includes('header') ||
                className.includes('menu') || className.includes('toolbar') ||
                className.includes('sidebar') || className.includes('aside') ||
                className.includes('banner') || className.includes('footer')) {
                score -= 30;
            }
        }

        // Special penalty for elements in typical sidebar/margin positions
        var isInMargin = rect.left < 200 || rect.right > window.innerWidth - 200;
        if (isInMargin) {
            score -= 20;
            console.debug('get-xpath-at-point.js: Penalizing margin element');
        }

        // Boost for elements in main content area (center of page)
        var pageCenter = window.innerWidth / 2;
        var elementCenter = (rect.left + rect.right) / 2;
        var distanceFromCenter = Math.abs(elementCenter - pageCenter);
        var centerBoost = Math.max(0, 20 - (distanceFromCenter / pageCenter) * 20);
        score += centerBoost;

        // Boost for elements that are likely main content based on common class names
        if (element.className && typeof element.className === 'string') {
            var className = element.className.toLowerCase();
            if (className.includes('main') || className.includes('content') ||
                className.includes('article') || className.includes('post') ||
                className.includes('entry') || className.includes('body')) {
                score += 25;
                console.debug('get-xpath-at-point.js: Boosting main content element');
            }
        }

        // Boost for common main content container IDs
        if (element.id && typeof element.id === 'string') {
            var id = element.id.toLowerCase();
            if (id.includes('main') || id.includes('content') ||
                id.includes('article') || id.includes('post') ||
                id === 'mw-content-text' || // Wikipedia main content
                id.includes('bodyContent')) {
                score += 30;
                console.debug('get-xpath-at-point.js: Boosting main content ID element');
            }
        }

        // Exclude script, style, and other non-visible elements
        if (['script', 'style', 'meta', 'link', 'title', 'noscript'].includes(tagName)) {
            return 0;
        }

        var finalScore = Math.max(1, score); // Ensure minimum score of 1
        console.debug('get-xpath-at-point.js: Element score:', finalScore);
        return finalScore;
    }

    // Function to check if a text fragment is unique on the page
    function isTextFragmentUnique(textFragment) {
        if (!textFragment || textFragment.length < 10) return false;

        var bodyText = document.body.textContent || document.body.innerText || '';
        var normalizedBodyText = bodyText.replace(/\s+/g, ' ').toLowerCase();
        var normalizedFragment = textFragment.replace(/\s+/g, ' ').toLowerCase();

        // Count occurrences
        var occurrences = 0;
        var index = 0;
        while ((index = normalizedBodyText.indexOf(normalizedFragment, index)) !== -1) {
            occurrences++;
            index += normalizedFragment.length;
            if (occurrences > 1) break; // Early exit if not unique
        }

        return occurrences === 1;
    }

    // Function to highlight an element briefly
    function highlightElement(element) {
        var originalOutline = element.style.outline;
        var originalOutlineOffset = element.style.outlineOffset;

        element.style.outline = '2px solid #007AFF';
        element.style.outlineOffset = '2px';

        setTimeout(function() {
            element.style.outline = originalOutline;
            element.style.outlineOffset = originalOutlineOffset;
        }, 2000);
    }
})();
