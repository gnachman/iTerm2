class CopyMode {
    constructor() {
        console.debug("[copymode] CopyMode constructor called");
        this.enabled = false;
        this.selecting = false;
        this.mode = SelectionMode.CHARACTER;
        this.selectionStart = null;  // DOM position when selection started
        this.cursor = null;
        console.debug("[copymode] Creating CursorMovement instance");
        this.movement = new CursorMovement();

        // Wait for DOM to be ready
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => this.init());
        } else {
            this.init();
        }
    }

    init() {
        console.debug("[copymode] init() called");
        console.debug("[copymode] Creating Cursor instance");
        this.cursor = new Cursor();
        // Don't initialize cursor position until copy mode is enabled
    }

    initializeCursorPosition() {
        // Find the first visible text node to position cursor at
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

        let node;
        while (node = walker.nextNode()) {
            // Test if this text node has visible dimensions
            try {
                const range = document.createRange();
                range.setStart(node, 0);
                range.setEnd(node, Math.min(1, node.textContent.length));
                const rect = range.getBoundingClientRect();

                if (rect.width > 0 && rect.height > 0) {
                    console.debug(`[copymode] Found visible text node: "${node.textContent.substring(0, 30)}..." with rect ${rect.width}x${rect.height}`);
                    this.cursor.setPosition(node, 0);
                    return;
                } else {
                    console.debug(`[copymode] Skipping text node with zero dimensions: "${node.textContent.substring(0, 20)}..."`);
                }
            } catch (e) {
                console.debug(`[copymode] Error testing text node: "${node.textContent.substring(0, 20)}..."`, e);
            }
        }

        console.debug(`[copymode] No visible text nodes found, cursor not positioned`);
    }


    enable() {
        console.debug("[copymode] Enable called");
        this.enabled = true;
        // Initialize cursor position on first enable
        this.initializeCursorPosition();
        this.cursor.show();
        console.debug(`[copymode] Cursor enabled`);
        return true;
    }

    disable() {
        try {
            console.debug("[copymode] Disable called");
            this.enabled = false;
            this.setSelecting(false);
            this.selectionStart = null;
            this.cursor.hide();
        } catch(e) {
            console.error(e.toString());
            console.error(e);
        }
        // Selection persists after exiting copy mode
        return true;
    }

    moveBackwardWord() {
        console.debug(`[copymode] moveBackwardWord() called`);
        const newPosition = this.movement.moveBackwardWord(this.cursor.textNode, this.cursor.characterOffset);
        if (newPosition) {
            console.debug(`[copymode] moveBackwardWord successful`);
            this.cursor.setPosition(newPosition.textNode, newPosition.characterOffset);
            this.scrollCursorIntoView();
            this.updateSelection();
            return true;
        }
        return false;
    }

    moveForwardWord() {
        console.debug(`[copymode] moveForwardWord() called`);
        const newPosition = this.movement.moveForwardWord(this.cursor.textNode, this.cursor.characterOffset);
        if (newPosition) {
            console.debug(`[copymode] moveForwardWord successful`);
            this.cursor.setPosition(newPosition.textNode, newPosition.characterOffset);
            this.scrollCursorIntoView();
            this.updateSelection();
            return true;
        }
        return false;
    }
    moveBackwardBigWord() {
        console.debug(`[copymode] moveBackwardBigWord() called`);
        const newPosition = this.movement.moveBackwardBigWord(this.cursor.textNode, this.cursor.characterOffset);
        if (newPosition) {
            console.debug(`[copymode] moveBackwardBigWord successful`);
            this.cursor.setPosition(newPosition.textNode, newPosition.characterOffset);
            this.scrollCursorIntoView();
            this.updateSelection();
            return true;
        }
        return false;
    }

    moveForwardBigWord() {
        console.debug(`[copymode] moveForwardBigWord() called`);
        const newPosition = this.movement.moveForwardBigWord(this.cursor.textNode, this.cursor.characterOffset);
        if (newPosition) {
            console.debug(`[copymode] moveForwardBigWord successful`);
            this.cursor.setPosition(newPosition.textNode, newPosition.characterOffset);
            this.scrollCursorIntoView();
            this.updateSelection();
            return true;
        }
        return false;
    }
    moveLeft() {
        console.debug(`[copymode] moveLeft() called`);
        console.debug(`[copymode] Current cursor DOM position: textNode="${this.cursor.textNode?.textContent?.substring(0, 20)}...", offset=${this.cursor.characterOffset}`);

        const newPosition = this.movement.moveLeft(this.cursor.textNode, this.cursor.characterOffset);
        if (newPosition) {
            console.debug(`[copymode] moveLeft successful, updating cursor position`);
            this.cursor.setPosition(newPosition.textNode, newPosition.characterOffset);
            this.scrollCursorIntoView();
            this.updateSelection();
            return true;
        } else {
            console.debug(`[copymode] moveLeft failed, no valid position found`);
            return false;
        }
    }

    moveRight() {
        console.debug(`[copymode] moveRight() called`);
        console.debug(`[copymode] Current cursor DOM position: textNode="${this.cursor.textNode?.textContent?.substring(0, 20)}...", offset=${this.cursor.characterOffset}`);

        const newPosition = this.movement.moveRight(this.cursor.textNode, this.cursor.characterOffset);
        if (newPosition) {
            console.debug(`[copymode] moveRight successful, updating cursor position`);
            this.cursor.setPosition(newPosition.textNode, newPosition.characterOffset);
            this.scrollCursorIntoView();
            this.updateSelection();
            return true;
        } else {
            console.debug(`[copymode] moveRight failed, no valid position found`);
            return false;
        }
    }
    moveUp(skipScrollIntoView = false) {
        console.debug(`[copymode] moveUp() called`);
        console.debug(`[copymode] Current cursor DOM position: textNode="${this.cursor.textNode?.textContent?.substring(0, 20)}...", offset=${this.cursor.characterOffset}`);

        const newPosition = this.movement.moveUp(this.cursor.textNode, this.cursor.characterOffset);
        if (newPosition) {
            console.debug(`[copymode] moveUp successful, updating cursor position`);
            this.cursor.setPosition(newPosition.textNode, newPosition.characterOffset);
            if (!skipScrollIntoView) {
                this.scrollCursorIntoView();
            }
            this.updateSelection();
            return true;
        } else {
            console.debug(`[copymode] moveUp failed, no valid position found`);
            return false;
        }
    }
    moveDown(skipScrollIntoView = false) {
        try {
            console.debug(`[copymode] moveDown() called`);
            console.debug(`[copymode] Current cursor DOM position: textNode="${this.cursor.textNode?.textContent?.substring(0, 20)}...", offset=${this.cursor.characterOffset}`);

            const newPosition = this.movement.moveDown(this.cursor.textNode, this.cursor.characterOffset);
            if (newPosition) {
                console.debug(`[copymode] moveDown successful, updating cursor position`);
                this.cursor.setPosition(newPosition.textNode, newPosition.characterOffset);
                if (!skipScrollIntoView) {
                    this.scrollCursorIntoView();
                }
                this.updateSelection();
                return true;
            } else {
                console.debug(`[copymode] moveDown failed, no valid position found`);
                // Log current cursor state for debugging
                console.debug(`[copymode] Cursor remains at: textNode="${this.cursor.textNode?.textContent?.substring(0, 20)}...", offset=${this.cursor.characterOffset}`);
                return false;
            }
        } catch(e) {
            console.error(e.toString());
            console.error(e);
            return false;
        }
    }

    // Helper method for page movement
    moveByDistance(direction, targetDistance) {
        console.debug(`[copymode] moveByDistance ${direction} for ${targetDistance}px`);
        if (!this.cursor || !this.cursor.textNode) {
            console.debug(`[copymode] moveByDistance: no cursor or text node`);
            return false;
        }

        const startCoords = this.cursor.getPageCoordinates();
        if (!startCoords) {
            console.debug(`[copymode] moveByDistance: could not get starting coordinates`);
            return false;
        }

        let moved = false;
        let attempts = 0;
        const maxAttempts = 1000;

        while (attempts < maxAttempts) {
            // Skip scroll-into-view during bulk movement to prevent auto-scrolling that negates the movement
            const moveSuccess = direction === 'up' ? this.moveUp(true) : this.moveDown(true);
            if (!moveSuccess) {
                console.debug(`[copymode] moveByDistance: move${direction} failed, stopping at attempt ${attempts}`);
                break;
            }

            moved = true;
            attempts++;

            const currentCoords = this.cursor.getPageCoordinates();
            if (!currentCoords) break;

            const distanceMoved = direction === 'up'
                ? startCoords.pageY - currentCoords.pageY
                : currentCoords.pageY - startCoords.pageY;

            if (distanceMoved >= targetDistance) {
                console.debug(`[copymode] moveByDistance: reached target distance ${distanceMoved}px, stopping`);
                break;
            }
        }

        // Do a single scroll-into-view at the end of the bulk movement
        if (moved) {
            this.scrollCursorIntoView();
        }

        console.debug(`[copymode] moveByDistance completed: moved=${moved}, attempts=${attempts}`);
        return moved;
    }

    pageUp() {
        return this.moveByDistance('up', window.innerHeight);
    }

    pageDown() {
        return this.moveByDistance('down', window.innerHeight);
    }

    pageUpHalfScreen() {
        return this.moveByDistance('up', window.innerHeight / 2);
    }

    pageDownHalfScreen() {
        return this.moveByDistance('down', window.innerHeight / 2);
    }
    previousMark() { return false; }
    nextMark() { return false; }

    // Helper method to find first or last visible position in document
    findDocumentBoundary(isStart) {
        const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            {
                acceptNode: function(node) {
                    // For document boundaries, only filter truly hidden content, not scrolled content
                    return isTextNodeVisible(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                }
            },
            false
        );

        let targetNode = null;
        if (isStart) {
            targetNode = walker.nextNode();
        } else {
            // Find last node
            let node;
            while (node = walker.nextNode()) {
                targetNode = node;
            }
        }

        if (!targetNode) {
            console.debug(`[copymode] findDocumentBoundary: no visible text nodes found`);
            return null;
        }

        // Find first/last visible character position
        const text = targetNode.textContent;
        const range = isStart ? [0, text.length] : [text.length - 1, -1];
        const step = isStart ? 1 : -1;

        for (let i = range[0]; i !== range[1]; i += step) {
            if (this.movement.isPositionVisible(targetNode, i)) {
                console.debug(`[copymode] findDocumentBoundary: found ${isStart ? 'first' : 'last'} visible position at offset ${i}`);
                return { textNode: targetNode, characterOffset: i };
            }
        }

        console.debug(`[copymode] findDocumentBoundary: target text node has no visible positions`);
        return null;
    }

    moveToStart() {
        console.debug(`[copymode] moveToStart() called`);
        const position = this.findDocumentBoundary(true);
        if (position) {
            this.cursor.setPosition(position.textNode, position.characterOffset);
            this.scrollCursorIntoView();
            this.updateSelection();
            return true;
        }
        return false;
    }

    moveToEnd() {
        console.debug(`[copymode] moveToEnd() called`);
        const position = this.findDocumentBoundary(false);
        if (position) {
            this.cursor.setPosition(position.textNode, position.characterOffset);
            this.scrollCursorIntoView();
            this.updateSelection();
            return true;
        }
        return false;
    }
    moveToStartOfIndentation() {
        return this.moveToLineEdge(true);
    }

    // Helper method to move cursor to a target Y position in the viewport
    moveToViewportPosition(targetY) {
        console.debug(`[copymode] moveToViewportPosition: target=${targetY}`);

        // Convert viewport Y to page coordinates
        const scrollY = window.pageYOffset || document.documentElement.scrollTop;
        const targetPageY = targetY + scrollY;

        console.debug(`[copymode] moveToViewportPosition: targetPageY=${targetPageY}, scrollY=${scrollY}`);

        // Find the best text position near this Y coordinate
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

        let bestPosition = null;
        let bestDistance = Infinity;
        let candidateCount = 0;
        let node;

        while (node = walker.nextNode()) {
            const text = node.textContent;

            for (let i = 0; i < text.length; i++) {
                const coords = this.movement.getPageCoordinates(node, i);
                if (!coords) continue;

                candidateCount++;
                const distance = Math.abs(coords.pageY - targetPageY);

                if (distance < bestDistance) {
                    bestDistance = distance;
                    bestPosition = { textNode: node, characterOffset: i };
                }

                // Early exit if we find something very close
                if (distance < 20) {
                    break;
                }
            }

            // Early exit if we found something very close
            if (bestDistance < 20) {
                break;
            }
        }

        console.debug(`[copymode] moveToViewportPosition: checked ${candidateCount} candidates, best distance: ${bestDistance}`);

        if (bestPosition) {
            console.debug(`[copymode] moveToViewportPosition: moving to offset ${bestPosition.characterOffset}`);
            this.cursor.setPosition(bestPosition.textNode, bestPosition.characterOffset);
            this.scrollCursorIntoView();
            this.updateSelection();
            return true;
        }

        console.debug(`[copymode] moveToViewportPosition: no suitable position found`);
        return false;
    }

    moveToBottomOfVisibleArea() {
        const viewportHeight = window.innerHeight;
        const targetY = viewportHeight - 50; // 50px from bottom
        return this.moveToViewportPosition(targetY);
    }

    moveToMiddleOfVisibleArea() {
        const viewportHeight = window.innerHeight;
        const targetY = viewportHeight / 2; // Middle of viewport
        return this.moveToViewportPosition(targetY);
    }

    moveToTopOfVisibleArea() {
        const targetY = 50; // 50px from top
        return this.moveToViewportPosition(targetY);
    }
    // Helper method to move to start or end of line within the same block
    moveToLineEdge(isStart) {
        console.debug(`[copymode] moveToLineEdge: ${isStart ? 'start' : 'end'}`);
        if (!this.cursor || !this.cursor.textNode) {
            console.debug(`[copymode] moveToLineEdge: no cursor or text node`);
            return false;
        }

        const currentCoords = this.cursor.getPageCoordinates();
        if (!currentCoords) {
            console.debug(`[copymode] moveToLineEdge: could not get current coordinates`);
            return false;
        }

        // Get the current block element (parent that defines the line)
        let currentBlock = this.cursor.textNode.parentElement;
        while (currentBlock && !this.isBlockElement(currentBlock)) {
            currentBlock = currentBlock.parentElement;
        }

        if (!currentBlock) {
            currentBlock = this.cursor.textNode.parentElement; // Fallback
        }

        console.debug(`[copymode] moveToLineEdge: current block is ${currentBlock.tagName}`);

        // Find all text positions within this block on approximately the same line
        const targetY = currentCoords.pageY;
        const lineThreshold = 2; // Very tight threshold to stay on same line

        const walker = document.createTreeWalker(
            currentBlock,
            NodeFilter.SHOW_TEXT,
            {
                acceptNode: function(node) {
                    return isTextNodeVisible(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                }
            },
            false
        );

        let bestPosition = null;
        let bestX = isStart ? Infinity : -Infinity;
        let candidateCount = 0;
        let node;

        while (node = walker.nextNode()) {
            const text = node.textContent;

            for (let i = 0; i < text.length; i++) {
                const coords = this.movement.getPageCoordinates(node, i);
                if (!coords) continue;

                // Check if this position is on approximately the same line
                if (Math.abs(coords.pageY - targetY) > lineThreshold) {
                    continue;
                }

                candidateCount++;

                // Find leftmost (start) or rightmost (end) position
                const isBetter = isStart ? coords.pageX < bestX : coords.pageX > bestX;
                if (isBetter) {
                    bestX = coords.pageX;
                    bestPosition = { textNode: node, characterOffset: i };
                }
            }
        }

        console.debug(`[copymode] moveToLineEdge: checked ${candidateCount} candidates on same line`);

        if (bestPosition && bestPosition.textNode !== this.cursor.textNode || bestPosition.characterOffset !== this.cursor.characterOffset) {
            console.debug(`[copymode] moveToLineEdge: moving to ${isStart ? 'leftmost' : 'rightmost'} position at X=${bestX}`);
            this.cursor.setPosition(bestPosition.textNode, bestPosition.characterOffset);
            this.scrollCursorIntoView();
            this.updateSelection();
            return true;
        }

        console.debug(`[copymode] moveToLineEdge: already at ${isStart ? 'start' : 'end'} of line`);
        return false;
    }

    // Helper to determine if an element is a block-level element
    isBlockElement(element) {
        const blockTags = ['DIV', 'P', 'SECTION', 'ARTICLE', 'HEADER', 'FOOTER', 'MAIN', 'NAV', 'ASIDE', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'BLOCKQUOTE', 'PRE', 'UL', 'OL', 'LI'];
        return blockTags.includes(element.tagName) || getComputedStyle(element).display.includes('block');
    }

    moveToStartOfLine() {
        return this.moveToLineEdge(true);
    }

    moveToEndOfLine() {
        return this.moveToLineEdge(false);
    }

    moveToStartOfNextLine() {
        const moved = this.moveDown();
        if (moved) {
            this.moveToStartOfLine();
        }
        return moved;
    }

    getCharacterRect(textNode, characterOffset) {
        try {
            const range = document.createRange();
            range.setStart(textNode, characterOffset);
            range.setEnd(textNode, Math.min(characterOffset + 1, textNode.textContent.length));

            // Use getClientRects() for accurate single-character positioning
            const rects = range.getClientRects();
            if (rects.length === 0) return null;
            const rect = rects[rects.length - 1];

            if (rect.width > 0 && rect.height > 0) {
                const scrollX = window.pageXOffset || document.documentElement.scrollLeft;
                const scrollY = window.pageYOffset || document.documentElement.scrollTop;
                return {
                    left: rect.left + scrollX,
                    top: rect.top + scrollY,
                    right: rect.right + scrollX,
                    bottom: rect.bottom + scrollY,
                    width: rect.width,
                    height: rect.height
                };
            }
        } catch (e) {
            // Skip invalid positions
        }
        return null;
    }



    swap() {
        console.debug(`[copymode] swap() called`);

        // Only swap if we're currently selecting and have a selection start point
        if (!this.selecting || !this.selectionStart) {
            console.debug(`[copymode] swap: not selecting or no selection start point, doing nothing`);
            return false;
        }

        // Store current cursor position
        const currentCursorPos = {
            textNode: this.cursor.textNode,
            characterOffset: this.cursor.characterOffset
        };

        console.debug(`[copymode] swap: moving cursor from "${currentCursorPos.textNode?.textContent?.substring(0, 20)}...", offset ${currentCursorPos.characterOffset}`);
        console.debug(`[copymode] swap: moving cursor to "${this.selectionStart.textNode?.textContent?.substring(0, 20)}...", offset ${this.selectionStart.characterOffset}`);

        // Move cursor to where selection started
        this.cursor.setPosition(this.selectionStart.textNode, this.selectionStart.characterOffset);

        // Move selection start to where cursor was
        this.selectionStart = {
            textNode: currentCursorPos.textNode,
            characterOffset: currentCursorPos.characterOffset
        };

        // Update the visual selection and scroll cursor into view
        this.scrollCursorIntoView();
        this.updateSelection();

        console.debug(`[copymode] swap: selection start now at "${this.selectionStart.textNode?.textContent?.substring(0, 20)}...", offset ${this.selectionStart.characterOffset}`);

        return true;
    }
    scrollUp() {
        const oldScrollY = window.pageYOffset;
        window.scrollBy(0, -20);
        return window.pageYOffset !== oldScrollY;
    }
    scrollDown() {
        const oldScrollY = window.pageYOffset;
        window.scrollBy(0, 20);
        return window.pageYOffset !== oldScrollY;
    }

    scrollCursorIntoView() {
        if (!this.enabled) return;

        const cursorRect = this.cursor.getBoundingRect();
        if (!cursorRect) {
            console.debug(`[copymode] scrollCursorIntoView: no cursor rect available`);
            return;
        }

        const viewportHeight = window.innerHeight;
        const viewportWidth = window.innerWidth;
        const scrollPadding = 50;

        console.debug(`[copymode] scrollCursorIntoView: cursor at viewport (${cursorRect.left}, ${cursorRect.top}), viewport size ${viewportWidth}x${viewportHeight}`);

        let scrolled = false;

        if (cursorRect.top < scrollPadding) {
            console.debug(`[copymode] Scrolling up: cursor.top ${cursorRect.top} < padding ${scrollPadding}`);
            window.scrollBy(0, cursorRect.top - scrollPadding);
            scrolled = true;
        } else if (cursorRect.bottom > viewportHeight - scrollPadding) {
            console.debug(`[copymode] Scrolling down: cursor.bottom ${cursorRect.bottom} > viewport ${viewportHeight - scrollPadding}`);
            window.scrollBy(0, cursorRect.bottom - viewportHeight + scrollPadding);
            scrolled = true;
        }

        if (cursorRect.left < scrollPadding) {
            console.debug(`[copymode] Scrolling left: cursor.left ${cursorRect.left} < padding ${scrollPadding}`);
            window.scrollBy(cursorRect.left - scrollPadding, 0);
            scrolled = true;
        } else if (cursorRect.right > viewportWidth - scrollPadding) {
            console.debug(`[copymode] Scrolling right: cursor.right ${cursorRect.right} > viewport ${viewportWidth - scrollPadding}`);
            window.scrollBy(cursorRect.right - viewportWidth + scrollPadding, 0);
            scrolled = true;
        }

        if (scrolled) {
            console.debug(`[copymode] Page scrolled, updating cursor display`);
            // Since we're using page coordinates for CSS positioning,
            // no need to update display - cursor should stay in correct position
        } else {
            console.debug(`[copymode] Cursor already visible, no scroll needed`);
        }
    }

    async copySelection() {
        console.debug("[copymode] copyselection");
        const selection = window.getSelection();
        const selectedText = selection.toString();

        if (selectedText) {
            try {
                console.debug(`[copymode] copy ${selectedText}`);
                await navigator.clipboard.writeText(selectedText);
                return true;
            } catch (err) {
                console.error('Failed to copy to clipboard:', err);
                return false;
            }
        }
        return false;
    }

    setMode(newMode) {
        this.mode = newMode;
    }

    setSelecting(selecting) {
        if (selecting === this.selecting) {
            return;
        }
        console.debug(`[copymode] set selecting to ${selecting}`);

        this.selecting = selecting;

        if (selecting) {
            // Save current cursor position as selection start
            if (this.cursor && this.cursor.textNode) {
                this.selectionStart = {
                    textNode: this.cursor.textNode,
                    characterOffset: this.cursor.characterOffset
                };
                console.debug(`[copymode] Selection started at: "${this.selectionStart.textNode.textContent.substring(0, 20)}...", offset ${this.selectionStart.characterOffset}`);
            }
        }
        // When selecting is turned off, keep the selection visible
        // It should only be cleared when copy mode is disabled entirely

        // Update cursor appearance
        if (this.cursor) {
            this.cursor.setSelecting(selecting);
        }
    }

    updateSelection() {
        if (!this.selecting || !this.selectionStart || !this.cursor || !this.cursor.textNode) {
            return;
        }

        // Create a range from selection start to current cursor position
        try {
            const range = document.createRange();
            const selection = window.getSelection();

            // Compare positions to set range in correct order
            const startFirst = this.comparePositions(
                this.selectionStart.textNode,
                this.selectionStart.characterOffset,
                this.cursor.textNode,
                this.cursor.characterOffset
            ) <= 0;

            if (startFirst) {
                range.setStart(this.selectionStart.textNode, this.selectionStart.characterOffset);
                range.setEnd(this.cursor.textNode, this.cursor.characterOffset);
            } else {
                range.setStart(this.cursor.textNode, this.cursor.characterOffset);
                range.setEnd(this.selectionStart.textNode, this.selectionStart.characterOffset);
            }

            selection.removeAllRanges();
            selection.addRange(range);

            console.debug(`[copymode] Selection updated from start to cursor`);
        } catch (e) {
            console.debug(`[copymode] Error updating selection:`, e);
        }
    }

    comparePositions(node1, offset1, node2, offset2) {
        // Returns: -1 if pos1 before pos2, 0 if same, 1 if pos1 after pos2
        if (node1 === node2) {
            return offset1 - offset2;
        }

        const position = node1.compareDocumentPosition(node2);
        if (position & Node.DOCUMENT_POSITION_FOLLOWING) {
            return -1;
        } else if (position & Node.DOCUMENT_POSITION_PRECEDING) {
            return 1;
        }
        return 0;
    }

    getState() {
        return {
            enabled: this.enabled,
            selecting: this.selecting,
            mode: this.mode,
            selectionStart: this.selectionStart ? { ...this.selectionStart } : null
        };
    }
}
