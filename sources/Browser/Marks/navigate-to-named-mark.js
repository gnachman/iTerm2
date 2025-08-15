(function() {
    console.debug('navigate-to-named-mark.js: Starting navigation');

    // Include mark location utilities
    {{INCLUDE:mark-locator.js}}

    // Parameters passed via template substitution
    var xpath = "{{XPATH}}";
    var offsetY = parseInt("{{OFFSET_Y}}") || 0;
    var scrollY = parseInt("{{SCROLL_Y}}") || 0;
    var y = parseInt("{{Y}}") || 0;
    var textFragment = "{{TEXT_FRAGMENT}}";

    console.debug('navigate-to-named-mark.js: Parameters - xpath:', xpath, 'offsetY:', offsetY, 'scrollY:', scrollY, 'textFragment:', textFragment, 'y:', y);

    // Create mark object for locator
    var mark = {
        xpath: xpath,
        offsetY: offsetY,
        y: y,
        textFragment: textFragment
    };

    try {
        // Use the common mark locator to find position
        var scrollInfo = calculateScrollPosition(mark);

        if (!scrollInfo) {
            console.debug('navigate-to-named-mark.js: No valid position found, cannot navigate');
            return false;
        }

        console.debug('navigate-to-named-mark.js: Found position using strategy:', scrollInfo.strategy);
        console.debug('navigate-to-named-mark.js: Scrolling to:', scrollInfo.scrollY);

        // Smooth scroll to position
        window.scrollTo({
            top: scrollInfo.scrollY,
            left: 0,
            behavior: 'smooth'
        });

        // Highlight element if found
        if (scrollInfo.element) {
            var originalOutline = scrollInfo.element.style.outline;
            var originalOutlineOffset = scrollInfo.element.style.outlineOffset;

            scrollInfo.element.style.outline = '2px solid #007AFF';
            scrollInfo.element.style.outlineOffset = '2px';

            setTimeout(function() {
                scrollInfo.element.style.outline = originalOutline;
                scrollInfo.element.style.outlineOffset = originalOutlineOffset;
            }, 2000);
        }

        console.debug('navigate-to-named-mark.js: Navigation successful');
        return true; // Successfully navigated

    } catch (error) {
        console.debug('navigate-to-named-mark.js: Error navigating to mark:', error);
        console.debug('navigate-to-named-mark.js: Error stack:', error.stack);
        return false;
    }
})();
