(function() {
    'use strict';

    let navigationBubbles = [];
    let currentPrefix = '';
    let keyListener = null;
    let currentCallback = null;
    let segments = [];
    let matches = [];
    let globalBubbleRegistry = []; // Maps labels to match data for cross-frame lookup

    // Generate shortcut labels ensuring no shortcut is a prefix of another
    // This mirrors the Objective-C implementation exactly
    function generateShortcutLabels(count) {
        const labels = [];
        let i = 0;

        // First 9 are numbers 1-9
        while (i < Math.min(count, 9)) {
            labels.push((i + 1).toString());
            i++;
        }

        // For remaining items, calculate how many digits are needed
        if (count > 9) {
            const remainingCount = count - 9;
            let digits = 1;
            let cardinality = 26;
            
            // Calculate minimum digits needed so all shortcuts have same length
            while (cardinality < remainingCount) {
                digits++;
                cardinality *= 26;
            }

            let r = 0;
            while (i < count) {
                let label = '';
                let temp = r;
                // Build label with exact number of digits
                while (label.length < digits) {
                    label = String.fromCharCode(65 + (temp % 26)) + label;
                    temp = Math.floor(temp / 26);
                }
                labels.push(label);
                i++;
                r++;
            }
        }

        return labels;
    }

    // Create CSS styles for bubbles
    function createStyles() {
        if (document.getElementById('find-nav-styles')) {
            return;
        }

        const style = document.createElement('style');
        style.id = 'find-nav-styles';
        style.textContent = `
            .find-nav-bubble {
                position: absolute;
                background-color: #007AFF;
                color: white;
                border-radius: 50%;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                font-size: 12px;
                font-weight: 600;
                text-align: center;
                display: flex;
                align-items: center;
                justify-content: center;
                z-index: 10000;
                pointer-events: none;
                opacity: 0;
                transform: scale(0.8);
                transition: opacity 0.2s ease-in-out, transform 0.2s ease-in-out;
                min-width: 24px;
                min-height: 24px;
                box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
            }

            .find-nav-bubble.visible {
                opacity: 1;
                transform: scale(1);
            }

            .find-nav-bubble.highlighted {
                background-color: #FF3B30;
                animation: find-nav-pulse 0.6s ease-in-out infinite alternate;
            }

            @keyframes find-nav-pulse {
                from { transform: scale(1); }
                to { transform: scale(1.1); }
            }

            .find-nav-bubble.dissolve {
                opacity: 0;
                transform: scale(1.2);
                transition: opacity 0.3s ease-out, transform 0.3s ease-out;
            }
        `;
        document.head.appendChild(style);
    }

    // Get position for placing bubble using the engine's match bounds
    async function getBubblePosition(match, instanceId, index) {
        const engine = getEngine(instanceId);
        if (!engine) {
            console.error('find-nav: No engine found for instanceId:', instanceId);
            return null;
        }

        console.debug(`find-nav: Getting position for match ${index}:`, {
            matchId: match.id,
            type: match.type,
            text: match.text.substring(0, 30) + '...',
            coordinates: match.coordinates,
            hasHighlightElements: !!match.highlightElements,
            highlightElementsCount: match.highlightElements?.length
        });

        // For local matches, use the engine's getLocalMatchBounds directly
        if (match.type === 'local') {
            // Make sure we have highlight elements
            if (!match.highlightElements || match.highlightElements.length === 0) {
                console.error(`find-nav: Match ${index} has no highlight elements`);
                // Try to find the match by its ID in the engine's matches array
                const engineMatch = engine.matches.find(m => m.id === match.id);
                if (engineMatch && engineMatch.highlightElements) {
                    console.debug(`find-nav: Found match in engine with ${engineMatch.highlightElements.length} highlight elements`);
                    match = engineMatch;
                } else {
                    console.error(`find-nav: Could not find match ${match.id} in engine matches`);
                    return null;
                }
            }
            
            // Log what highlight elements we're using
            if (match.highlightElements && match.highlightElements.length > 0) {
                const firstElement = match.highlightElements[0];
                const rect = firstElement.getBoundingClientRect();
                console.debug(`find-nav: Match ${index} first highlight element:`, {
                    tagName: firstElement.tagName,
                    className: firstElement.className,
                    textContent: firstElement.textContent?.substring(0, 30),
                    viewportRect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
                });
            }
            
            const bounds = engine.getLocalMatchBounds(match);
            console.debug(`find-nav: Local match ${index} bounds:`, bounds, 'from', match.highlightElements?.length, 'elements');
            
            if (!bounds || bounds.x === undefined) {
                console.error(`find-nav: No bounds for local match ${index}`);
                return null;
            }
            // Position bubble above and centered on the match
            const position = {
                x: bounds.x + bounds.width / 2 - 12,
                y: bounds.y - 30
            };
            console.debug(`find-nav: Bubble ${index} position:`, position);
            return position;
        } 
        // For remote matches (iframes), use the engine's getRemoteMatchBounds
        else if (match.type === 'remote') {
            console.debug(`find-nav: Getting remote bounds for match ${index}`);
            const bounds = await engine.getRemoteMatchBounds(match);
            console.debug(`find-nav: Remote match ${index} bounds:`, bounds);
            
            if (!bounds || !bounds.x) {
                console.error(`find-nav: No bounds for remote match ${index}`);
                return null;
            }
            // Position bubble above and centered on the match
            const position = {
                x: bounds.x + bounds.width / 2 - 12,
                y: bounds.y - 30
            };
            console.debug(`find-nav: Bubble ${index} position:`, position);
            return position;
        }

        console.error(`find-nav: Unknown match type for match ${index}:`, match.type);
        return null;
    }

    // Create and position a navigation bubble
    function createBubble(label, position, match) {
        const bubble = document.createElement('div');
        bubble.className = 'find-nav-bubble';
        bubble.textContent = label;
        bubble.style.left = position.x + 'px';
        bubble.style.top = (position.y + window.scrollY) + 'px';
        
        // Adjust bubble size for longer labels
        if (label.length > 2) {
            bubble.style.minWidth = (label.length * 8 + 16) + 'px';
            bubble.style.borderRadius = '12px';
        }
        
        // Store match data for callback
        bubble._match = match;
        bubble._label = label;

        document.body.appendChild(bubble);
        
        // Animate in
        requestAnimationFrame(() => {
            bubble.classList.add('visible');
        });

        return bubble;
    }

    // Remove all navigation bubbles with animation
    function removeBubbles() {
        navigationBubbles.forEach(bubble => {
            bubble.classList.add('dissolve');
            setTimeout(() => {
                if (bubble.parentNode) {
                    bubble.parentNode.removeChild(bubble);
                }
            }, 300);
        });
        navigationBubbles = [];
    }

    // Remove a specific bubble by label across all frames
    function removeBubbleByLabel(label) {
        const script = `
            (function() {
                const label = ${JSON.stringify(label)};
                const bubbles = document.querySelectorAll('[data-find-nav-bubble="true"]');
                bubbles.forEach(bubble => {
                    if (bubble.textContent === label) {
                        bubble.classList.add('dissolve');
                        setTimeout(() => {
                            if (bubble.parentNode) {
                                bubble.parentNode.removeChild(bubble);
                            }
                        }, 300);
                    }
                });
                console.debug('find-nav: Removed bubble with label "' + label + '"');
            })();
        `;
        
        graphDiscoveryEvaluateInAll(script, () => {});
    }

    // Check if characters are a prefix of any shortcut
    // This mirrors shortcutNavigationCharactersAreCommandPrefix exactly
    function isCommandPrefix(characters) {
        return globalBubbleRegistry.some(entry => {
            return entry.label.toLowerCase().startsWith(characters.toLowerCase());
        });
    }

    // Find exact match for characters
    // This mirrors shortcutNavigationActionForKeyEquivalent exactly
    function findMatchForKeyEquivalent(characters) {
        return globalBubbleRegistry.find(entry => {
            return entry.label.toLowerCase() === characters.toLowerCase();
        });
    }

    // Update bubble highlighting based on current prefix across all frames
    // This mirrors shortcutNavigationDidSetPrefix exactly
    function updateBubbleHighlighting(prefix) {
        const script = `
            (function() {
                const prefix = ${JSON.stringify(prefix)};
                const bubbles = document.querySelectorAll('[data-find-nav-bubble="true"]');
                bubbles.forEach(bubble => {
                    const label = bubble.textContent;
                    const matches = label.toLowerCase().startsWith(prefix.toLowerCase());
                    bubble.classList.toggle('highlighted', matches && prefix.length > 0);
                });
                console.debug('find-nav: Updated highlighting for prefix "' + prefix + '" on', bubbles.length, 'bubbles');
            })();
        `;
        
        graphDiscoveryEvaluateInAll(script, () => {});
    }

    // Handle keyboard input - mirroring iTermShortcutNavigationModeHandler exactly
    function handleKeyEvent(event) {
        // Check for command/control modifiers that should be ignored
        const mask = event.metaKey || event.ctrlKey;
        if (mask) {
            return false;
        }

        if (event.key.length === 0) {
            return false;
        }

        // Handle escape to exit (maps to character 27 in ObjC code)
        if (event.key === 'Escape') {
            clearNavigation();
            return true;
        }

        console.debug('find-nav: Key pressed:', event.key);

        const character = event.key.toUpperCase();
        let candidate = currentPrefix ? currentPrefix + character : character;

        // Check for exact match with current prefix + character
        const exactMatch = findMatchForKeyEquivalent(candidate);
        if (exactMatch) {
            console.debug('find-nav: Found exact match for', candidate, 'with text:', exactMatch.text);
            
            if (currentCallback && exactMatch.text) {
                currentCallback(exactMatch.text);
            }
            
            // Clear all navigation - this removes all bubbles at once
            clearNavigation();
            
            return true;
        }

        // Check for single character exact match (without prefix)
        const singleMatch = findMatchForKeyEquivalent(character);
        if (singleMatch) {
            console.debug('find-nav: Found single match for', character, 'with text:', singleMatch.text);
            
            if (currentCallback && singleMatch.text) {
                currentCallback(singleMatch.text);
            }
            
            // Clear all navigation - this removes all bubbles at once
            clearNavigation();
            
            return true;
        }

        // Check if candidate is a valid prefix
        if (isCommandPrefix(candidate)) {
            currentPrefix = candidate;
            updateBubbleHighlighting(currentPrefix);
            event.preventDefault();
            return true;
        }

        // Invalid input, ignore
        return false;
    }

    // Public API function: Start navigation mode
    async function startNavigation(segmentsParam, matchesParam, instanceId, callback) {
        console.debug('find-nav: Starting navigation with', matchesParam?.length, 'matches');
        
        // Clear any existing navigation
        clearNavigation();
        
        segments = segmentsParam || [];
        matches = matchesParam || [];
        currentCallback = callback;
        currentPrefix = '';
        globalBubbleRegistry = [];

        if (!matches || matches.length === 0) {
            console.debug('find-nav: No matches to navigate');
            return;
        }

        // Ensure styles are loaded
        createStyles();

        // Generate shortcut labels with fixed digit count
        const labels = generateShortcutLabels(matches.length);
        console.debug('find-nav: Generated labels:', labels);
        
        // Populate global registry for keyboard handling
        for (let index = 0; index < matches.length; index++) {
            const match = matches[index];
            globalBubbleRegistry.push({
                label: labels[index],
                text: match.text,
                match: match
            });
        }
        console.debug('find-nav: Populated global registry with', globalBubbleRegistry.length, 'entries');
        
        // Create a match mapping based on coordinates and text that works across frames
        const matchLabels = [];
        for (let index = 0; index < matches.length; index++) {
            const match = matches[index];
            if (match.type === 'local') {
                // For local matches, use the match directly
                matchLabels.push({
                    label: labels[index],
                    coordinates: match.coordinates,
                    text: match.text,
                    frameId: null // Main frame
                });
            } else if (match.type === 'remote') {
                // For remote matches, we need to map back to the original iframe coordinates
                // Remote coordinates are [iframeSegmentIndex, ...originalCoordinates]
                const originalCoordinates = match.coordinates.slice(1); // Remove iframe segment index
                matchLabels.push({
                    label: labels[index],
                    coordinates: originalCoordinates,
                    text: match.text,
                    frameId: match.frameId
                });
            }
        }
        
        console.debug('find-nav: Created match labels for', matchLabels.length, 'matches');
        
        // Use evaluateInAll to let each frame create its own bubbles
        const script = `
            (function() {
                const matchLabels = ${JSON.stringify(matchLabels)};
                const instanceId = ${JSON.stringify(instanceId)};
                
                // The getEngine function is inside the IIFE, but we can access it via a hack
                console.debug('find-nav: Checking for iTermCustomFind:', typeof window.iTermCustomFind);
                
                if (!window.iTermCustomFind) {
                    console.debug('find-nav: Frame does not have iTermCustomFind loaded, skipping');
                    return;
                }
                
                // Access the INSTANCES map that should be available in this frame's scope
                // This is a bit hacky but should work since both are in the same IIFE
                let engine = null;
                try {
                    // Try to access the engine through eval since we're in the same IIFE context
                    engine = eval('getEngine')(instanceId);
                } catch (e) {
                    console.debug('find-nav: Could not access getEngine:', e.message);
                    return;
                }
                
                console.debug('find-nav: Engine found:', !!engine);
                console.debug('find-nav: Engine has matches:', engine ? !!engine.matches : false);
                console.debug('find-nav: Match count:', engine ? (engine.matches ? engine.matches.length : 0) : 0);
                
                if (!engine || !engine.matches || engine.matches.length === 0) {
                    console.debug('find-nav: No engine or matches in frame, skipping');
                    return;
                }
                
                console.debug('find-nav: Frame processing', engine.matches.length, 'matches');
                
                // Create styles if needed
                if (!document.getElementById('find-nav-styles')) {
                    const style = document.createElement('style');
                    style.id = 'find-nav-styles';
                    style.textContent = \`
                        .find-nav-bubble {
                            position: absolute;
                            background-color: #007AFF;
                            color: white;
                            border-radius: 50%;
                            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                            font-size: 12px;
                            font-weight: 600;
                            text-align: center;
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            z-index: 10000;
                            pointer-events: none;
                            opacity: 0;
                            transform: scale(0.8);
                            transition: opacity 0.2s ease-in-out, transform 0.2s ease-in-out;
                            min-width: 24px;
                            min-height: 24px;
                            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
                        }
                        .find-nav-bubble.visible {
                            opacity: 1;
                            transform: scale(1);
                        }
                        .find-nav-bubble.highlighted {
                            background-color: #FF3B30;
                            animation: find-nav-pulse 0.6s ease-in-out infinite alternate;
                        }
                        @keyframes find-nav-pulse {
                            from { transform: scale(1); }
                            to { transform: scale(1.1); }
                        }
                        .find-nav-bubble.dissolve {
                            opacity: 0;
                            transform: scale(1.2);
                            transition: opacity 0.3s ease-out, transform 0.3s ease-out;
                        }
                    \`;
                    document.head.appendChild(style);
                }
                
                // Determine if this is the main frame or an iframe
                const isMainFrame = window === window.top;
                
                // Create bubbles for matches in this frame
                let bubblesCreated = 0;
                engine.matches.forEach((match, index) => {
                    // Find the label for this match by matching coordinates and text
                    let matchLabel = null;
                    for (const labelInfo of matchLabels) {
                        if (isMainFrame && labelInfo.frameId === null) {
                            // Main frame match
                            if (JSON.stringify(labelInfo.coordinates) === JSON.stringify(match.coordinates) && 
                                labelInfo.text === match.text) {
                                matchLabel = labelInfo.label;
                                break;
                            }
                        } else if (!isMainFrame && labelInfo.frameId) {
                            // Iframe match - compare coordinates and text
                            if (JSON.stringify(labelInfo.coordinates) === JSON.stringify(match.coordinates) && 
                                labelInfo.text === match.text) {
                                matchLabel = labelInfo.label;
                                break;
                            }
                        }
                    }
                    
                    if (!matchLabel) {
                        return; // No label for this match
                    }
                    
                    console.debug('find-nav: Creating bubble for match', match.id, 'with label', matchLabel, 'coords', match.coordinates);
                    
                    const bounds = engine.getLocalMatchBounds(match);
                    if (!bounds || bounds.x === undefined) {
                        console.error('find-nav: No bounds for match', match.id);
                        return;
                    }
                    
                    // Create bubble
                    const bubble = document.createElement('div');
                    bubble.className = 'find-nav-bubble';
                    bubble.textContent = matchLabel;
                    bubble.style.left = (bounds.x + bounds.width / 2 - 12) + 'px';
                    bubble.style.top = (bounds.y - 30) + 'px';
                    
                    if (matchLabel.length > 2) {
                        bubble.style.minWidth = (matchLabel.length * 8 + 16) + 'px';
                        bubble.style.borderRadius = '12px';
                    }
                    
                    // Store for cleanup
                    bubble.setAttribute('data-find-nav-bubble', 'true');
                    bubble.setAttribute('data-match-id', match.id);
                    
                    document.body.appendChild(bubble);
                    
                    // Animate in
                    requestAnimationFrame(() => {
                        bubble.classList.add('visible');
                    });
                    
                    bubblesCreated++;
                });
                
                console.debug('find-nav: Frame created', bubblesCreated, 'bubbles');
            })();
        `;
        
        console.debug('find-nav: Using evaluateInAll to create bubbles in all frames');
        
        await new Promise((resolve) => {
            graphDiscoveryEvaluateInAll(script, (results) => {
                console.debug('find-nav: evaluateInAll completed, results from', Object.keys(results).length, 'frames');
                resolve();
            });
        });

        // Add keyboard listener to main frame only
        if (!keyListener) {
            keyListener = (event) => {
                if (handleKeyEvent(event)) {
                    event.preventDefault();
                    event.stopPropagation();
                }
            };
            document.addEventListener('keydown', keyListener, true);
        }
        
        console.debug('find-nav: Keyboard listener added to main frame');
    }

    // Public API function: Clear navigation mode
    function clearNavigation() {
        if (keyListener) {
            document.removeEventListener('keydown', keyListener, true);
            keyListener = null;
        }
        
        // Clear bubbles in all frames using evaluateInAll
        const script = `
            (function() {
                // Remove all navigation bubbles in this frame
                const bubbles = document.querySelectorAll('[data-find-nav-bubble="true"]');
                bubbles.forEach(bubble => {
                    bubble.classList.add('dissolve');
                    setTimeout(() => {
                        if (bubble.parentNode) {
                            bubble.parentNode.removeChild(bubble);
                        }
                    }, 300);
                });
                console.debug('find-nav: Cleared', bubbles.length, 'bubbles from frame');
            })();
        `;
        
        // Use evaluateInAll to clear bubbles in all frames
        graphDiscoveryEvaluateInAll(script, () => {});
        
        currentPrefix = '';
        currentCallback = null;
        segments = [];
        matches = [];
        globalBubbleRegistry = [];
    }

    // Expose public API
    window.findNav = {
        startNavigation: startNavigation,
        clearNavigation: clearNavigation
    };

    // Make API immutable
    Object.freeze(window.findNav);
    Object.freeze(window.findNav.startNavigation);
    Object.freeze(window.findNav.clearNavigation);

})();
