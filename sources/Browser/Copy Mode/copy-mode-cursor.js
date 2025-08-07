//
//  copy-mode-cursor.js
//  iTerm2
//
//  Created by George Nachman on 7/31/25.
//

class Cursor {
    constructor() {
        this.element = null;
        // Cursor position in DOM coordinates (textNode + character offset)
        // These coordinates are completely layout and scroll invariant
        this.textNode = null;
        this.characterOffset = 0;
        this.visible = false;
        this.selecting = false;
        // Don't create element in constructor - wait until first use
    }

    setSelecting(selecting) {
        this.selecting = selecting;
        this.ensureElementExists();
        if (this.svgPath) {
            // Update cursor appearance when selecting state changes
            this.updateDisplay();
        }
    }

    ensureElementExists() {
        if (this.element) {
            return; // Already created
        }
        this.createElement();
    }

    createElement() {
        this.element = document.createElement('div');
        this.element.id = 'iterm-copy-mode-cursor';
        this.element.style.cssText = `
            position: absolute;
            width: 0;
            height: 0;
            z-index: 10000;
            pointer-events: none;
            display: none;
        `;

        // Create SVG for the cursor shape to match iTerm2's native cursor
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.style.cssText = `
            position: absolute;
            left: 0;
            top: 0;
            overflow: visible;
        `;
        svg.setAttribute('width', '24');
        svg.setAttribute('height', '24');

        // Create the cursor path (triangle + stem)
        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        path.setAttribute('stroke', 'black');
        path.setAttribute('stroke-width', '1');
        path.setAttribute('fill', 'white');
        // Path will be updated in updateCursorPath() based on character height

        svg.appendChild(path);
        this.element.appendChild(svg);
        this.svgPath = path;
        this.svg = svg;

        if (document.body) {
            document.body.appendChild(this.element);
        }
    }

    setPosition(textNode, characterOffset) {
        // Validate inputs
        if (!textNode || textNode.nodeType !== Node.TEXT_NODE) {
            return;
        }

        if (characterOffset < 0 || characterOffset > textNode.textContent.length) {
            return;
        }

        this.textNode = textNode;
        this.characterOffset = characterOffset;
        this.ensureElementExists();
        this.updateDisplay();
    }

    updateDisplay() {
        if (this.element && this.textNode) {
            // Convert DOM coordinates directly to CSS positioning (page coordinates)
            const rect = this.getPageCoordinates();
            if (rect) {
                // Update cursor shape based on character height
                const triangleWidth = this.updateCursorPath(rect.height);

                // Position cursor so the tip of triangle (where stem attaches) is at character boundary
                // This requires shifting left by half the triangle width
                const offsetX = triangleWidth / 2;
                this.element.style.left = (rect.pageX - offsetX) + 'px';
                this.element.style.top = rect.pageY + 'px';
            }
        }
    }

    updateCursorPath(characterHeight) {
        // Match iTerm2 cursor design:
        // - Triangle takes top 1/3 of character height, pointing downward
        // - Stem width is 2px when not selecting, 4px when selecting
        const triangleHeight = characterHeight / 3;
        const stemWidth = this.selecting ? 4 : 2;
        const halfStemWidth = stemWidth / 2;

        // Get actual character width by measuring "M" in the current font
        const characterWidth = this.getCharacterWidth();

        // Triangle width matches character width (like terminal cell width)
        const triangleWidth = characterWidth;

        // Path points (relative to cursor position):
        // Start at left corner of triangle, go to tip, then attach stem
        const pathData = `
            M ${-triangleWidth/2} 0
            L ${-halfStemWidth} ${triangleHeight}
            L ${-halfStemWidth} ${characterHeight}
            L ${halfStemWidth} ${characterHeight}
            L ${halfStemWidth} ${triangleHeight}
            L ${triangleWidth/2} 0
            Z
        `;

        this.svgPath.setAttribute('d', pathData);

        // Update SVG size to accommodate the shape
        this.svg.setAttribute('width', triangleWidth);
        this.svg.setAttribute('height', characterHeight);
        this.svg.setAttribute('viewBox', `${-triangleWidth/2} 0 ${triangleWidth} ${characterHeight}`);

        // Update fill color based on selecting state
        this.svgPath.setAttribute('fill', this.selecting ? '#C1DEFF' : 'white');

        // Return triangle width so caller can adjust positioning
        return triangleWidth;
    }

    getCharacterWidth() {
        // Measure the width of "M" in the current font context
        if (!this.textNode || !this.textNode.parentElement) {
            return 10; // Fallback width
        }

        // Create a temporary span with "M" to measure
        const measureSpan = document.createElement('span');
        measureSpan.textContent = 'M';
        measureSpan.style.cssText = `
            position: absolute;
            visibility: hidden;
            white-space: pre;
        `;

        // Insert it as a sibling to get the same font styling
        this.textNode.parentElement.appendChild(measureSpan);
        const width = measureSpan.getBoundingClientRect().width;
        measureSpan.remove();

        return width || 10; // Return measured width or fallback
    }

    getPageCoordinates() {
        return getTextNodePageCoordinates(this.textNode, this.characterOffset);
    }

    show() {
        this.visible = true;
        this.ensureElementExists();
        if (this.element) {
            this.element.style.display = 'block';
            this.updateDisplay(); // Make sure position is set when showing
        }
    }

    hide() {
        this.visible = false;
        if (this.element) {
            this.element.style.display = 'none';
        }
    }

    getBoundingRect() {
        if (!this.element) {
            return null;
        }
        return this.element.getBoundingClientRect();
    }
}
