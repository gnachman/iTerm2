//
//  copy-mode-cursor-movement.js
//  iTerm2
//
//  Created by George Nachman on 7/31/25.
//

class CursorMovement {
    constructor() {
        // This class computes new cursor positions for movement in various directions
    }


    // Visual movement - up/down try to maintain horizontal position
    moveUp(currentTextNode, currentCharacterOffset) {
        return this.moveVertical(currentTextNode, currentCharacterOffset, 'up');
    }

    moveDown(currentTextNode, currentCharacterOffset) {
        return this.moveVertical(currentTextNode, currentCharacterOffset, 'down');
    }

    moveVertical(currentTextNode, currentCharacterOffset, direction) {
        if (!currentTextNode) {
            return null;
        }

        // Get current line rectangle using Range API
        const currentLineRect = this.getCurrentLineRect(currentTextNode, currentCharacterOffset);
        if (!currentLineRect) {
            return null;
        }

        if (direction === 'down') {
            return this.findTextBelow(currentLineRect, currentTextNode, currentCharacterOffset);
        } else {
            return this.findTextAbove(currentLineRect, currentTextNode, currentCharacterOffset);
        }
    }

    getCurrentLineRect(textNode, characterOffset) {
        try {
            // Create a range for the current character position
            const range = document.createRange();
            range.setStart(textNode, characterOffset);
            range.setEnd(textNode, Math.min(characterOffset + 1, textNode.textContent.length));

            // Use getClientRects() for accurate single-character positioning
            const rects = range.getClientRects();
            if (rects.length === 0) return null;
            const rect = rects[rects.length - 1];

            // Convert to page coordinates
            const scrollX = window.pageXOffset || document.documentElement.scrollLeft;
            const scrollY = window.pageYOffset || document.documentElement.scrollTop;

            return {
                top: rect.top + scrollY,
                bottom: rect.bottom + scrollY,
                left: rect.left + scrollX,
                right: rect.right + scrollX,
                width: rect.width,
                height: rect.height
            };
        } catch (e) {
            return null;
        }
    }

    findTextBelow(currentLineRect, currentTextNode = null, currentCharacterOffset = 0) {
        return this.findTextInDirection('down', currentLineRect, currentTextNode, currentCharacterOffset);
    }

    findTextAbove(currentLineRect, currentTextNode = null, currentCharacterOffset = 0) {
        return this.findTextInDirection('up', currentLineRect, currentTextNode, currentCharacterOffset);
    }

    findTextInDirection(direction, currentLineRect, currentTextNode = null, currentCharacterOffset = 0) {

        // Use the unified intelligent algorithm to find all candidates
        const candidates = this.getAllMoveCandidates(direction, currentLineRect, currentTextNode, currentCharacterOffset);

        if (candidates.length === 0) {
            return null;
        }

        // Return the best candidate (already sorted by score)
        const best = candidates[0];

        return {
            textNode: best.textNode,
            characterOffset: best.characterOffset
        };
    }

    getPageCoordinates(textNode, characterOffset) {
        return getTextNodePageCoordinates(textNode, characterOffset);
    }

    // Logical movement - left/right can jump between DOM nodes
    moveLeft(currentTextNode, currentCharacterOffset) {
        return this.moveHorizontal(currentTextNode, currentCharacterOffset, 'left');
    }

    moveRight(currentTextNode, currentCharacterOffset) {
        return this.moveHorizontal(currentTextNode, currentCharacterOffset, 'right');
    }

    moveHorizontal(currentTextNode, currentCharacterOffset, direction) {

        if (!currentTextNode) {
            return null;
        }

        if (direction === 'right') {
            // Try to move right within current text node

            // If we're already at the end of the text node, move to the next node immediately
            if (currentCharacterOffset >= currentTextNode.textContent.length) {
            } else {
                // If we're at the last character position, skip trying to move within the node
                // and go directly to the next node
                if (currentCharacterOffset === currentTextNode.textContent.length - 1) {
                    // Don't return here, fall through to move to next node
                } else {
                    // Search for next visible character in the same text node
                    for (let offset = currentCharacterOffset + 1; offset <= currentTextNode.textContent.length; offset++) {

                        if (this.isPositionVisible(currentTextNode, offset)) {
                            return { textNode: currentTextNode, characterOffset: offset };
                        }
                    }

                }
            }

            // Move to next text node
            const nextNode = this.findNextTextNode(currentTextNode);
            if (nextNode) {
                return nextNode;
            } else {
                // Fallback: try visual movement when DOM order fails
                return this.findVisuallyNextTextNode(currentTextNode);
            }
        } else {
            // Try to move left within current text node
            if (currentCharacterOffset > 0) {
                // Search for previous visible character in the same text node
                for (let offset = currentCharacterOffset - 1; offset >= 0; offset--) {

                    if (this.isPositionVisible(currentTextNode, offset)) {
                        return { textNode: currentTextNode, characterOffset: offset };
                    }
                }

            }

            // Move to previous text node
            const prevNode = this.findPreviousTextNode(currentTextNode);
            if (prevNode) {
                return prevNode;
            } else {
                // Fallback: try visual movement when DOM order fails
                return this.findVisuallyPreviousTextNode(currentTextNode);
            }
        }
    }

    isPositionVisible(textNode, characterOffset) {
        const coords = this.getPageCoordinates(textNode, characterOffset);
        // Position is visible if we get valid coordinates with non-zero dimensions
        return coords && coords.pageX >= 0 && coords.pageY >= 0;
    }

    findNextTextNode(currentNode) {
        const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            {
                acceptNode: function(node) {
                    return isTextNodeVisible(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                }
            },
            false
        );

        // Find current node in the walker
        let node;
        while (node = walker.nextNode()) {
            if (node === currentNode) {
                // Found current node, get next one
                const nextNode = walker.nextNode();
                if (nextNode) {

                    // Find first visible character position in this node
                    const text = nextNode.textContent;
                    for (let i = 0; i <= text.length; i++) {
                        if (this.isPositionVisible(nextNode, i)) {
                            return { textNode: nextNode, characterOffset: i };
                        }
                    }

                    // This node has no visible positions, try the next one
                    return this.findNextTextNode(nextNode);
                } else {
                    return null;
                }
            }
        }

        return null;
    }

    findPreviousTextNode(currentNode) {
        const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            {
                acceptNode: function(node) {
                    return isTextNodeVisible(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                }
            },
            false
        );

        let previousNode = null;
        let node;

        // Walk through nodes until we find current node
        while (node = walker.nextNode()) {
            if (node === currentNode) {
                if (previousNode) {

                    // Find last visible character position in this node
                    const text = previousNode.textContent;
                    for (let i = text.length - 1; i >= 0; i--) {
                        if (this.isPositionVisible(previousNode, i)) {
                            return { textNode: previousNode, characterOffset: i };
                        }
                    }

                    // This node has no visible positions, try the previous one
                    return this.findPreviousTextNode(previousNode);
                } else {
                    return null;
                }
            }
            previousNode = node;
        }

        return null;
    }

    findVisuallyNextTextNode(currentNode) {
        // Get current position for visual comparison
        const currentCoords = this.getPageCoordinates(currentNode, 0);
        if (!currentCoords) {
            return null;
        }


        const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            {
                acceptNode: function(node) {
                    return isTextNodeVisible(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                }
            },
            false
        );

        let bestNode = null;
        let bestDistance = Infinity;
        let candidateCount = 0;
        let node;

        while (node = walker.nextNode()) {
            if (node === currentNode) continue; // Skip current node

            const nodeCoords = this.getPageCoordinates(node, 0);
            if (!nodeCoords) continue;

            // Look for nodes that are visually to the right and close vertically
            if (nodeCoords.pageX > currentCoords.pageX) {
                candidateCount++;
                const dx = nodeCoords.pageX - currentCoords.pageX;
                const dy = Math.abs(nodeCoords.pageY - currentCoords.pageY);
                // Prefer nodes that are close horizontally and vertically
                const distance = dx + 2 * dy; // Weight vertical distance more

                if (distance < bestDistance) {
                    bestDistance = distance;
                    bestNode = node;
                }
            }
        }

        if (bestNode) {
            return { textNode: bestNode, characterOffset: 0 };
        } else {
            return null;
        }
    }

    findVisuallyPreviousTextNode(currentNode) {
        // Get current position for visual comparison
        const currentCoords = this.getPageCoordinates(currentNode, 0);
        if (!currentCoords) {
            return null;
        }


        const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            {
                acceptNode: function(node) {
                    return isTextNodeVisible(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                }
            },
            false
        );

        let bestNode = null;
        let bestDistance = Infinity;
        let candidateCount = 0;
        let node;

        while (node = walker.nextNode()) {
            if (node === currentNode) continue; // Skip current node

            const nodeCoords = this.getPageCoordinates(node, 0);
            if (!nodeCoords) continue;

            // Look for nodes that are visually to the left and close vertically
            if (nodeCoords.pageX < currentCoords.pageX) {
                candidateCount++;
                const dx = currentCoords.pageX - nodeCoords.pageX;
                const dy = Math.abs(nodeCoords.pageY - currentCoords.pageY);
                // Prefer nodes that are close horizontally and vertically
                const distance = dx + 2 * dy; // Weight vertical distance more

                if (distance < bestDistance) {
                    bestDistance = distance;
                    bestNode = node;
                }
            }
        }

        if (bestNode) {
            // Move to end of previous text node
            return { textNode: bestNode, characterOffset: Math.max(0, bestNode.textContent.length - 1) };
        } else {
            return null;
        }
    }

    // Word movement using browser's native word boundary detection
    moveByWord(currentTextNode, currentCharacterOffset, direction) {

        if (!currentTextNode) return null;

        // Use a temporary selection to find word boundaries
        const selection = window.getSelection();
        const savedRanges = [];

        // Save current selection
        for (let i = 0; i < selection.rangeCount; i++) {
            savedRanges.push(selection.getRangeAt(i).cloneRange());
        }

        try {
            // Create temporary selection at current position
            selection.removeAllRanges();
            const range = document.createRange();
            range.setStart(currentTextNode, currentCharacterOffset);
            range.setEnd(currentTextNode, currentCharacterOffset);
            selection.addRange(range);

            // Use browser's native word movement
            selection.modify('move', direction, 'word');

            // Get the new position
            if (selection.rangeCount > 0 && selection.anchorNode) {
                const newNode = selection.anchorNode;
                const newOffset = selection.anchorOffset;

                // Verify it's a text node we can use
                if (newNode.nodeType === Node.TEXT_NODE && isTextNodeVisible(newNode)) {
                    return { textNode: newNode, characterOffset: newOffset };
                }
            }
        } finally {
            // Restore original selection
            selection.removeAllRanges();
            savedRanges.forEach(range => selection.addRange(range));
        }

        return null;
    }

    // Character classification matching iTerm2's approach
    classifyCharacter(char, bigWords = false) {
        if (/\s/.test(char)) return 'whitespace';
        if (bigWords) {
            // For big words: only whitespace vs everything else
            return 'word'; // All non-whitespace is considered word
        }
        if (/\w/.test(char)) return 'word';
        return 'other'; // symbols, punctuation, etc.
    }

    moveForwardWord(currentTextNode, currentCharacterOffset) {
        if (!currentTextNode) return null;

        // Step 1: Skip the current "word" (same character class)
        let result = this.skipForwardByClass(currentTextNode, currentCharacterOffset);
        if (!result) return null;

        // Step 2: Skip any whitespace
        while (result) {
            const char = result.textNode.textContent[result.characterOffset];
            if (!char || this.classifyCharacter(char, false) !== 'whitespace') {
                break;
            }
            const next = this.moveRight(result.textNode, result.characterOffset);
            if (!next) break;
            result = next;
        }

        return result;
    }

    skipForwardByClass(textNode, offset) {
        if (!textNode || offset >= textNode.textContent.length) {
            return this.findNextVisiblePosition(textNode, offset);
        }

        const startChar = textNode.textContent[offset];
        const startClass = this.classifyCharacter(startChar, false);

        if (startClass === 'word') {
            // For word characters, use language-aware boundaries within a constrained window
            return this.skipForwardWord(textNode, offset);
        } else {
            // For other classes, skip to the first character of a different class
            return this.skipForwardSameClass(textNode, offset, startClass);
        }
    }

    skipForwardWord(textNode, offset) {
        // For word characters, we need smarter handling
        // First, use native word movement
        const selection = window.getSelection();
        const savedRanges = [];

        // Save current selection
        for (let i = 0; i < selection.rangeCount; i++) {
            savedRanges.push(selection.getRangeAt(i).cloneRange());
        }

        try {
            // Set selection at current position
            selection.removeAllRanges();
            const range = document.createRange();
            range.setStart(textNode, offset);
            range.setEnd(textNode, offset);
            selection.addRange(range);

            // Move forward by word
            selection.modify('move', 'forward', 'word');

            if (selection.anchorNode && selection.anchorNode.nodeType === Node.TEXT_NODE) {
                let newNode = selection.anchorNode;
                let newOffset = selection.anchorOffset;

                // Check if we landed on a non-word character
                if (newOffset < newNode.textContent.length) {
                    const char = newNode.textContent[newOffset];
                    if (this.classifyCharacter(char, false) !== 'word') {
                        // We're at the boundary, this is correct
                        return { textNode: newNode, characterOffset: newOffset };
                    }
                }

                // If we're still in a word, scan forward to find the actual boundary
                while (newNode) {
                    const text = newNode.textContent;
                    while (newOffset < text.length) {
                        const char = text[newOffset];
                        if (this.classifyCharacter(char, false) !== 'word') {
                            return { textNode: newNode, characterOffset: newOffset };
                        }
                        newOffset++;
                    }

                    // Try next node
                    const next = this.findNextTextNode(newNode);
                    if (!next) break;
                    newNode = next.textNode;
                    newOffset = 0;
                }
            }

            return null;
        } finally {
            // Restore selection
            selection.removeAllRanges();
            savedRanges.forEach(range => selection.addRange(range));
        }
    }

    skipForwardSameClass(textNode, offset, charClass) {
        let node = textNode;
        let pos = offset;

        while (node) {
            const text = node.textContent;

            // Skip characters of the same class
            while (pos < text.length) {
                const char = text[pos];
                if (this.classifyCharacter(char, false) !== charClass) {
                    return { textNode: node, characterOffset: pos };
                }
                pos++;
            }

            // Move to next node
            const next = this.findNextTextNode(node);
            if (!next) break;
            node = next.textNode;
            pos = 0;
        }

        return null;
    }


    findNextVisiblePosition(textNode, offset) {
        // Helper to find next visible position when at end of current node
        if (!textNode) return null;
        const next = this.findNextTextNode(textNode);
        return next;
    }

    moveBackwardWord(currentTextNode, currentCharacterOffset) {
        return this.moveByWord(currentTextNode, currentCharacterOffset, 'backward');
    }

    // Big word movement - implements iTerm2's two-phase algorithm
    moveForwardBigWord(currentTextNode, currentCharacterOffset) {
        if (!currentTextNode) return null;

        return this.moveBigWord(currentTextNode, currentCharacterOffset, 'forward');
    }

    moveBackwardBigWord(currentTextNode, currentCharacterOffset) {
        if (!currentTextNode) return null;

        return this.moveBigWord(currentTextNode, currentCharacterOffset, 'backward');
    }

    moveBigWord(currentTextNode, currentCharacterOffset, direction) {
        // Implement iTerm2's two-phase big word algorithm

        // Phase 1: Get current character class using big word rules
        const currentChar = currentTextNode.textContent[currentCharacterOffset];
        if (!currentChar) {
            return null;
        }

        const charClass = this.classifyCharacter(currentChar, true); // true = big words

        // Phase 2: Apply iTerm2's big word logic
        if (charClass === 'whitespace') {
            // On whitespace: move to start/end of adjacent non-whitespace region
            if (direction === 'forward') {
                return this.skipWhitespaceThenFindWordBoundary(currentTextNode, currentCharacterOffset, 'forward');
            } else {
                return this.skipWhitespaceThenFindWordBoundary(currentTextNode, currentCharacterOffset, 'backward');
            }
        } else {
            // On non-whitespace: find big word boundary, then move to start of next/previous word
            if (direction === 'forward') {
                const bigWordBoundary = this.findBigWordBoundary(currentTextNode, currentCharacterOffset, direction);
                if (!bigWordBoundary) return null;
                // Skip any whitespace after the big word boundary to find start of next word
                return this.skipWhitespaceThenFindWordStart(bigWordBoundary.textNode, bigWordBoundary.characterOffset);
            } else {
                // For backward: find start of current big word
                return this.findBigWordStart(currentTextNode, currentCharacterOffset);
            }
        }
    }

    findBigWordStart(textNode, offset) {
        // Find the start of the previous big word by moving backward
        let current = { textNode, characterOffset: offset };

        // Special case: if we're at offset 0, we're already at the start of this text node
        if (offset === 0) {
            // Move to previous text node to find previous big word
            const prevNodeResult = this.moveLeft(textNode, 0);
            if (!prevNodeResult) {
                return null;
            }

            // Find the start of the big word in the previous text node
            return this.findBigWordStartInPreviousContext(prevNodeResult.textNode, prevNodeResult.characterOffset);
        }

        // First, move backward to find the start of current big word
        let startOfCurrent = current;
        while (current) {
            const char = current.textNode.textContent[current.characterOffset];
            if (!char || this.classifyCharacter(char, true) === 'whitespace') {
                // Hit whitespace, startOfCurrent is the start of current big word
                break;
            }

            startOfCurrent = current;
            current = this.moveLeft(current.textNode, current.characterOffset);
        }

        // If we're already at the start of current big word, move to previous big word
        if (startOfCurrent.textNode === textNode && startOfCurrent.characterOffset === offset) {
            // We're at start of current big word, find previous one
            // Continue moving left through whitespace
            while (current) {
                const char = current.textNode.textContent[current.characterOffset];
                if (!char) {
                    break;
                }


                if (this.classifyCharacter(char, true) !== 'whitespace') {
                    // Found non-whitespace, this is part of the previous big word
                    // Now find the start of this big word by moving backward from here
                    let searchPos = current;
                    let prevStart = current;

                    while (searchPos) {
                        const searchChar = searchPos.textNode.textContent[searchPos.characterOffset];
                        if (!searchChar || this.classifyCharacter(searchChar, true) === 'whitespace') {
                            // Hit whitespace, prevStart is the start of previous big word
                            break;
                        }

                        prevStart = searchPos;
                        const nextSearchPos = this.moveLeft(searchPos.textNode, searchPos.characterOffset);

                        // Don't cross into different text nodes when finding the start
                        if (nextSearchPos && nextSearchPos.textNode !== searchPos.textNode) {
                            break;
                        }

                        searchPos = nextSearchPos;
                    }

                    return prevStart;
                }

                current = this.moveLeft(current.textNode, current.characterOffset);
            }

            return null; // No previous big word found
        }

        // Return start of current big word
        return startOfCurrent;
    }

    findBigWordStartInPreviousContext(textNode, offset) {
        // Find the start of a big word in a previous text node context

        // First, if we're in whitespace, skip to find non-whitespace
        let current = { textNode, characterOffset: offset };

        // Skip backward through whitespace to find the end of a big word
        while (current) {
            const char = current.textNode.textContent[current.characterOffset];
            if (!char) break;

            if (this.classifyCharacter(char, true) !== 'whitespace') {
                // Now find the start of this big word within the same text node
                let wordStart = current;
                while (current) {
                    const searchChar = current.textNode.textContent[current.characterOffset];
                    if (!searchChar || this.classifyCharacter(searchChar, true) === 'whitespace') {
                        return wordStart;
                    }

                    wordStart = current;
                    const prev = this.moveLeft(current.textNode, current.characterOffset);

                    // Don't cross text node boundaries
                    if (!prev || prev.textNode !== current.textNode) {
                        return wordStart;
                    }

                    current = prev;
                }
                return wordStart;
            }

            current = this.moveLeft(current.textNode, current.characterOffset);

            // Don't cross text node boundaries while looking for non-whitespace
            if (current && current.textNode !== textNode) {
                break;
            }
        }

        return null;
    }

    skipWhitespaceThenFindWordStart(textNode, offset) {
        // Skip whitespace and find the start of the next word
        let current = { textNode, characterOffset: offset };

        // Skip whitespace
        while (current) {
            const char = current.textNode.textContent[current.characterOffset];
            if (!char) break;

            if (this.classifyCharacter(char, true) !== 'whitespace') {
                // Found non-whitespace, this is the start of the next word
                return current;
            }

            current = this.moveRight(current.textNode, current.characterOffset);
        }

        return null;
    }

    skipWhitespaceThenFindWordBoundary(textNode, offset, direction) {
        // Skip whitespace first
        let current = { textNode, characterOffset: offset };

        // Skip all whitespace
        while (current) {
            const char = current.textNode.textContent[current.characterOffset];
            if (!char) break;

            if (this.classifyCharacter(char, true) !== 'whitespace') {
                // Found non-whitespace, now find word boundary
                if (direction === 'forward') {
                    return this.findBigWordBoundary(current.textNode, current.characterOffset, 'forward');
                } else {
                    return current; // For backward, we're already at the start
                }
            }

            // Move to next/previous character
            if (direction === 'forward') {
                current = this.moveRight(current.textNode, current.characterOffset);
            } else {
                current = this.moveLeft(current.textNode, current.characterOffset);
            }
        }

        return null;
    }

    findBigWordBoundary(textNode, offset, direction) {
        // Find boundary using big word classification (whitespace vs everything else)
        let current = { textNode, characterOffset: offset };

        while (current) {
            const char = current.textNode.textContent[current.characterOffset];
            if (!char) break;

            // In big word mode, boundary is whitespace
            if (this.classifyCharacter(char, true) === 'whitespace') {
                return current;
            }

            // Move to next/previous character
            if (direction === 'forward') {
                const next = this.moveRight(current.textNode, current.characterOffset);
                if (!next) return current; // End of text
                current = next;
            } else {
                const prev = this.moveLeft(current.textNode, current.characterOffset);
                if (!prev) return current; // Start of text
                current = prev;
            }
        }

        return current;
    }

    // Direction-aware score calculation
    calculateScoreForDirection(pageX, pageY, currentLineRect, direction) {
        const horizontalDistance = Math.abs(pageX - currentLineRect.left);
        const horizontalPenalty = horizontalDistance > 200 ? horizontalDistance * 2 : horizontalDistance;
        const lineStartBonus = -20;

        let verticalDistance;
        if (direction === 'down') {
            verticalDistance = pageY - currentLineRect.bottom;
        } else {
            verticalDistance = currentLineRect.top - pageY;
        }

        return horizontalPenalty + (verticalDistance * 0.3) + lineStartBonus;
    }

    // Unified helper function to check if element should be spatially pruned
    isElementSpatiallyPruned(element, currentLineRect, direction) {
        const rect = element.getBoundingClientRect();
        const scrollY = window.pageYOffset || document.documentElement.scrollTop;
        const elementTop = rect.top + scrollY;
        const elementBottom = rect.bottom + scrollY;

        // Maximum search distance (10000 pixels)
        const MAX_DISTANCE = 10000;

        if (direction === 'down') {
            // For moveDown: reject elements entirely above cursor or too far below
            return elementBottom <= currentLineRect.bottom ||
                   elementTop > currentLineRect.bottom + MAX_DISTANCE;
        } else {
            // For moveUp: reject elements entirely below cursor or too far above
            return elementTop >= currentLineRect.top ||
                   elementBottom < currentLineRect.top - MAX_DISTANCE;
        }
    }

    // Unified helper function to calculate theoretical best score for an element
    calculateElementBestPossibleScore(element, currentLineRect, direction) {
        const rect = element.getBoundingClientRect();
        const scrollY = window.pageYOffset || document.documentElement.scrollTop;

        const elementTop = rect.top + scrollY;
        const elementBottom = rect.bottom + scrollY;

        let bestPossibleY;
        if (direction === 'down') {
            // Best possible Y is the maximum of:
            // 1. Just below cursor line (currentLineRect.bottom)
            // 2. Element's top (if element is entirely below cursor)
            bestPossibleY = Math.max(currentLineRect.bottom, elementTop);
            // But it can't exceed the element's bottom
            bestPossibleY = Math.min(bestPossibleY, elementBottom);
        } else {
            // Best possible Y is the minimum of:
            // 1. Just above cursor line (currentLineRect.top)
            // 2. Element's bottom (if element is entirely above cursor)
            bestPossibleY = Math.min(currentLineRect.top, elementBottom);
            // But it can't be less than the element's top
            bestPossibleY = Math.max(bestPossibleY, elementTop);
        }

        // Calculate score with perfect horizontal alignment using direction-aware scoring
        return this.calculateScoreForDirection(currentLineRect.left, bestPossibleY, currentLineRect, direction);
    }

    // Unified helper function to extract direct text node children from an element
    extractDirectTextFromElement(element, currentLineRect, candidates, bestScore, direction, currentTextNode = null, currentCharacterOffset = 0, verbose=false) {
        let newBestScore = bestScore;
        let count = 0;

        // Check all direct child nodes of this element
        for (let child of element.childNodes) {
            if (child.nodeType === Node.TEXT_NODE) {
                const text = child.textContent;

                // Skip empty/whitespace-only text nodes
                if (!text.trim()) continue;

                // Skip invisible text nodes
                if (!isTextNodeVisible(child)) continue;

                // Check all character positions in this text node
                try {
                    const isSameTextNode = (child === currentTextNode);

                    for (let i = 0; i <= text.length; i++) {
                        count += 1;
                        const coords = this.getPageCoordinates(child, i);
                        if (coords) {
                            // Determine if this character position is a valid candidate
                            let isValidCandidate = false;

                            if (direction === 'down') {
                                if (isSameTextNode) {
                                    // Same text node: character must be after cursor position AND below cursor line
                                    if (i > currentCharacterOffset) {
                                        isValidCandidate = (coords.pageY > currentLineRect.bottom);
                                    }
                                } else {
                                    // Different text node: character must be below cursor line
                                    isValidCandidate = (coords.pageY > currentLineRect.bottom);
                                }
                            } else {
                                if (isSameTextNode) {
                                    // Same text node: character must be before cursor position AND above cursor line
                                    if (i < currentCharacterOffset) {
                                        isValidCandidate = (coords.pageY < currentLineRect.top);
                                    }
                                } else {
                                    // Different text node: character must be above cursor line
                                    isValidCandidate = (coords.pageY < currentLineRect.top);
                                }
                            }

                            if (isValidCandidate) {
                                const horizontalDistance = Math.abs(coords.pageX - currentLineRect.left);
                                const horizontalPenalty = horizontalDistance > 200 ? horizontalDistance * 2 : horizontalDistance;
                                const lineStartBonus = -20; // Bonus for line starts

                                let verticalDistance, score;
                                if (direction === 'down') {
                                    verticalDistance = coords.pageY - currentLineRect.bottom;
                                } else {
                                    verticalDistance = currentLineRect.top - coords.pageY;
                                }

                                // Skip candidates that are too far away (more than 10000 pixels)
                                if (verticalDistance > 10000) {
                                    continue;
                                }

                                score = horizontalPenalty + (verticalDistance * 0.3) + lineStartBonus;

                                candidates.push({
                                    textNode: child,
                                    characterOffset: i,
                                    coords: coords,
                                    horizontalDistance: horizontalDistance,
                                    verticalDistance: verticalDistance,
                                    score: score,
                                    char: text[i] || '[END]'
                                });

                                if (score < newBestScore) {
                                    newBestScore = score;
                                }
                            }
                        }
                    }
                } catch (e) {
                    // Skip text nodes that cause range errors
                    continue;
                }
            }
        }
        return newBestScore;
    }

    getAllMoveCandidates(direction, currentLineRect, currentTextNode = null, currentCharacterOffset = 0) {
        const stringifyRect = (rect, scrollY) => {
            const left = rect.left;
            const top = rect.top + scrollY;
            const width = rect.width;
            const height = rect.height;
            return `(${left}, ${top}) ${width} x ${height}`;
        };

        const boundaryY = direction === 'down' ? currentLineRect.bottom : currentLineRect.top;

        const startTime = performance.now();
        let candidates = [];
        let bestScore = Infinity;
        let elementsProcessed = 0;
        let elementsPruned = 0;
        let spatialPruned = 0;
        let competitivePruned = 0;
        let elementsWithText = 0;
        let bestScoreUpdates = 0;
        let elementsAbove = 0;
        let elementsBelow = 0;
        const scrollY = window.pageYOffset || document.documentElement.scrollTop;
        const self = this;

        const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_ELEMENT,
            {
                acceptNode: function(element) {
                    elementsProcessed++;

                    // Track elements above vs below cursor
                    const rect = element.getBoundingClientRect();
                    const elementTop = rect.top + scrollY;
                    const elementBottom = rect.bottom + scrollY;

                    if (direction === 'up') {
                        if (elementBottom < currentLineRect.top) {
                            elementsAbove++;
                        } else if (elementTop > currentLineRect.bottom) {
                            elementsBelow++;
                        }
                    } else {
                        if (elementTop > currentLineRect.bottom) {
                            elementsBelow++;
                        } else if (elementBottom < currentLineRect.top) {
                            elementsAbove++;
                        }
                    }

                    // Spatial pruning: reject entire subtrees on wrong side of cursor
                    if (self.isElementSpatiallyPruned(element, currentLineRect, direction)) {
                        spatialPruned++;
                        elementsPruned++;
                        return NodeFilter.FILTER_REJECT;
                    }

                    // Competitive pruning: reject if element can't possibly beat current best
                    if (bestScore < Infinity) {
                        const elementBestScore = self.calculateElementBestPossibleScore(element, currentLineRect, direction);
                        if (elementBestScore > bestScore) {
                            competitivePruned++;
                            elementsPruned++;
                            return NodeFilter.FILTER_REJECT;
                        }
                    }

                    // Element has potential - extract direct text candidates from it
                    const oldCandidateCount = candidates.length;
                    const oldBestScore = bestScore;
                    bestScore = self.extractDirectTextFromElement(element, currentLineRect, candidates, bestScore, direction, currentTextNode, currentCharacterOffset, (elementsProcessed % 100 == 0));

                    const newCandidates = candidates.length - oldCandidateCount;
                    if (newCandidates > 0) {
                        elementsWithText++;
                    }

                    // Track bestScore improvements for performance analysis
                    if (bestScore < oldBestScore) {
                        bestScoreUpdates++;
                    }

                    // Skip this element but continue recursing into its children
                    return NodeFilter.FILTER_SKIP;
                }
            },
            false
        );

        // Use reverse traversal for moveUp to improve competitive pruning performance
        if (direction === 'up') {
            // Start reverse traversal from current position instead of document bottom
            reverseTreeWalk(document.body, walker.filter.acceptNode);
        } else {
            // Trigger the TreeWalker to run (all work happens in the filter)
            while (walker.nextNode()) {
                // TreeWalker will never actually return nodes due to our filter logic
            }
        }

        const endTime = performance.now();
        const totalTime = endTime - startTime;

        // Sort by score (lower is better)
        const sortStart = performance.now();
        candidates.sort((a, b) => a.score - b.score);
        const sortTime = performance.now() - sortStart;

        return candidates;
    }

}

