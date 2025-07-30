(function() {
    'use strict';
    const secret = '{{SECRET}}';
    
    {{INCLUDE:copy-mode-util.js}}
    {{INCLUDE:copy-mode-cursor.js}}
    {{INCLUDE:copy-mode-cursor-movement.js}}
    {{INCLUDE:copy-mode-impl.js}}

    // Create singleton instance
    const copyMode = new CopyMode();

    // Export API
    window.iTerm2CopyMode = {
        enable: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.enable();
        },
        disable: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.disable();
        },

        get selecting() { return copyMode.selecting; },
        set selecting(value) {
            copyMode.setSelecting(value);
        },

        get mode() { return copyMode.mode; },
        set mode(value) { copyMode.setMode(value); },

        moveBackwardWord: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveBackwardWord();
        },
        moveForwardWord: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveForwardWord();
        },
        moveBackwardBigWord: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveBackwardBigWord();
        },
        moveForwardBigWord: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveForwardBigWord();
        },
        moveLeft: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveLeft();
        },
        moveRight: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveRight();
        },
        moveUp: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveUp();
        },
        moveDown: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveDown();
        },
        moveToStartOfNextLine: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveToStartOfNextLine();
        },
        pageUp: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.pageUp();
        },
        pageDown: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.pageDown();
        },
        pageUpHalfScreen: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.pageUpHalfScreen();
        },
        pageDownHalfScreen: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.pageDownHalfScreen();
        },
        previousMark: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.previousMark();
        },
        nextMark: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.nextMark();
        },
        moveToStart: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveToStart();
        },
        moveToEnd: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveToEnd();
        },
        moveToStartOfIndentation: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveToStartOfIndentation();
        },
        moveToBottomOfVisibleArea: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveToBottomOfVisibleArea();
        },
        moveToMiddleOfVisibleArea: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveToMiddleOfVisibleArea();
        },
        moveToTopOfVisibleArea: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveToTopOfVisibleArea();
        },
        moveToStartOfLine: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveToStartOfLine();
        },
        moveToEndOfLine: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.moveToEndOfLine();
        },
        swap: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.swap();
        },
        scrollUp: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.scrollUp();
        },
        scrollDown: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.scrollDown();
        },
        scrollCursorIntoView: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.scrollCursorIntoView();
        },
        copySelection: async (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return await copyMode.copySelection();
        },
        getState: (sessionSecret) => {
            if (sessionSecret !== secret) return;
            return copyMode.getState();
        }
    };
})();
