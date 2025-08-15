(function() {
    try {
        console.log("update-mark-positions.js starting");

        // Include mark location utilities
        {{INCLUDE:mark-locator.js}}

        var secret = "{{SECRET}}";
        var updates = [];

        console.log('update-mark-positions.js: Starting mark position update');

        // Get all current mark annotations to find their GUIDs and XPaths
        var annotations = document.querySelectorAll('.iterm-mark-annotation[data-mark-guid]');

        console.log('update-mark-positions.js: Found', annotations.length, 'mark annotations');

        for (var i = 0; i < annotations.length; i++) {
            var annotation = annotations[i];
            var guid = annotation.getAttribute('data-mark-guid');

            if (!guid) continue;

            // Get mark data from the annotation's data attributes
            var xpath = annotation.dataset.markXpath;
            var offsetY = parseInt(annotation.dataset.markOffsetY) || 0;
            var textFragment = annotation.dataset.markTextFragment;
            var y = annotation.dataset.y ? parseInt(annotation.dataset.y) : undefined;

            console.log('update-mark-positions.js: Updating position for mark:', guid);

            try {
                // Create mark object for locator
                var mark = {
                    xpath: xpath,
                    offsetY: offsetY,
                    textFragment: textFragment,
                    y: y
                };
                console.log(`update-mark-postions.js: Locate mark with xpath ${xpath}, textFragment ${textFragment}, y ${y}`);
                // Use common mark locator
                var locationInfo = locateMark(mark);

                if (locationInfo.element || locationInfo.strategy === 'absolute') {
                    var newScrollY = window.pageYOffset || document.documentElement.scrollTop;
                    var newOffsetY = (locationInfo.strategy === 'xpath') ? offsetY : 0;

                    console.log('update-mark-positions.js: Found position using strategy:', locationInfo.strategy);

                    updates.push({
                        guid: guid,
                        scrollY: Math.round(newScrollY),
                        offsetY: Math.round(newOffsetY),
                        elementTop: Math.round(locationInfo.documentPosition),
                        y: y
                    });
                } else {
                    console.log('update-mark-positions.js: No valid position found for mark:', guid);
                }
            } catch (error) {
                console.log('update-mark-positions.js: Error updating mark position:', error);
            }
        }

        console.log('update-mark-positions.js: Prepared', updates.length, 'position updates');

        // Re-enable layout change monitoring after processing the update
        console.log("Updating mark positions is finished");
        window.iTermLayoutChangeMonitor.reenableLayoutChangeMonitoring();

        return updates;
    } catch (e) {
        console.error(e.toString(), e);
        throw e;
    }
})();
