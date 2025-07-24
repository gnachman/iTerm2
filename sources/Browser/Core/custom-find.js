(function() {
    'use strict';

    // ==============================
    //  Multi-instance Find Engine
    // ==============================

    const TAG = '[iTermCustomFind]';
    const sessionSecret = "{{SECRET}}";
    const DEFAULT_INSTANCE_ID = 'default';

    // Global registry of engines on this page
    const INSTANCES = new Map();

    // Inject styles once
    const highlightStyles = `
         .iterm-find-highlight {
             background-color: #FFFF00 !important;
             color: #000000 !important;
             border-radius: 2px;
         }
         .iterm-find-highlight-current {
             background-color: #FF9632 !important;
             color: #000000 !important;
             border-radius: 2px;
         }
         .iterm-find-removed {
             display: none !important;
         }
     `;
    function injectStyles() {
        if (document.getElementById('iterm-find-styles')) {
            return;
        }
        
        // Wait for document.head to exist
        if (!document.head) {
            // If running at documentStart, defer until head is available
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', injectStyles, { once: true });
                console.debug(TAG, 'Deferring style injection until DOMContentLoaded');
                return;
            }
            console.debug(TAG, 'No document.head available');
            return;
        }
        
        const styleElement = document.createElement('style');
        styleElement.id = 'iterm-find-styles';
        styleElement.textContent = highlightStyles;
        document.head.appendChild(styleElement);
        console.debug(TAG, 'Styles injected');
    }
    injectStyles();

    // ------------------------------
    // Utility (instance-agnostic)
    // ------------------------------
    function safeStringify(obj) {
        try {
            return JSON.stringify(obj);
        } catch (_) {
            return String(obj);
        }
    }

    const SAFE_REVEAL_SELECTORS = [
        'details:not([open])',
        '.mw-collapsible',
        '.accordion',
        '[aria-expanded="false"]',
        '[data-collapsed="true"]'
    ];

    function ancestors(el) {
        const arr = [];
        for (let e = el; e; e = e.parentElement) {
            arr.push(e);
        }
        return arr;
    }

    // ==============================
    //  Engine Class
    // ==============================
    class FindEngine {
        constructor(instanceId) {
            this.instanceId = instanceId;

            // ---------- State ----------
            this.currentSearchTerm = '';
            this.currentMatchIndex = -1;
            this.searchMode = 'caseSensitive';
            this.contextLen = 0;

            this.segments = [];     // [{ node: Text, start: number, length: number, revealer: Element|null }]
            this.buffer = '';       // concatenated text
            this.matches = [];      // [{ start, end, els: HTMLElement[], rects?, revealers?: Set<Element> }]
            this.highlightedElements = [];
            this.hiddenSkippedCount = 0;

            // details elements we opened automatically for *any* match, so we can close on clear
            this.globallyAutoOpenedDetails = new Set();

            // other elements we force-visible; array of restore records
            this.revealRestores = [];

            // async token to ignore stale work
            this.opToken = 0;

            // scroll/resize debounce
            this.updateTimer = null;

            // listeners (once per instance)
            this.boundScheduleUpdate = () => { this.schedulePositionUpdate(); };
            window.addEventListener('scroll', this.boundScheduleUpdate, true);
            window.addEventListener('resize', this.boundScheduleUpdate);
        }

        log(...args) {
            console.debug(TAG, `[${this.instanceId}]`, ...args.map(a => (typeof a === 'object' ? safeStringify(a) : a)));
        }

        // ---------- Visibility helpers ----------
        isHidden(el) {
            for (let e = el; e; e = e.parentElement) {
                if (e.hasAttribute('hidden')) { return true; }
                if (e.getAttribute('aria-hidden') === 'true') { return true; }
                const cs = getComputedStyle(e);
                if (cs.display === 'none' || cs.visibility === 'hidden') { return true; }
            }
            return false;
        }

        firstRevealableAncestor(el) {
            for (let e = el; e; e = e.parentElement) {
                if (SAFE_REVEAL_SELECTORS.some(sel => { try { return e.matches(sel); } catch (_) { return false; } })) {
                    return e;
                }
            }
            return null;
        }

        forceVisible(el) {
            try {
                if (el.tagName === 'DETAILS' && !el.open) {
                    el.open = true;
                    this.globallyAutoOpenedDetails.add(el);
                    return;
                }

                if (el.hasAttribute('hidden')) {
                    this.revealRestores.push({ el, type: 'attr', attr: 'hidden', oldValue: '' });
                    el.removeAttribute('hidden');
                }

                if (el.getAttribute('aria-hidden') === 'true') {
                    this.revealRestores.push({ el, type: 'attr', attr: 'aria-hidden', oldValue: 'true' });
                    el.setAttribute('aria-hidden', 'false');
                }

                const cs = getComputedStyle(el);
                if (cs.display === 'none') {
                    this.revealRestores.push({ el, type: 'style-display', oldValue: el.style.display });
                    el.style.display = 'block';
                }
                if (cs.visibility === 'hidden') {
                    this.revealRestores.push({ el, type: 'style-visibility', oldValue: el.style.visibility });
                    el.style.visibility = 'visible';
                }

                if (el.matches('.mw-collapsible')) {
                    if (el.classList.contains('collapsed')) {
                        this.revealRestores.push({ el, type: 'class-remove-add', removed: 'collapsed' });
                        el.classList.remove('collapsed');
                    }
                }
                if (el.matches('[aria-expanded="false"]')) {
                    this.revealRestores.push({ el, type: 'attr', attr: 'aria-expanded', oldValue: el.getAttribute('aria-expanded') });
                    el.setAttribute('aria-expanded', 'true');
                }
                if (el.matches('[data-collapsed="true"]')) {
                    this.revealRestores.push({ el, type: 'attr', attr: 'data-collapsed', oldValue: el.getAttribute('data-collapsed') });
                    el.setAttribute('data-collapsed', 'false');
                }
            } catch (e) {
                this.log('forceVisible error:', e);
            }
        }

        // ---------- Clear ----------
        clearHighlights() {
            this.log('clearHighlights begin');
            const spans = document.querySelectorAll(`.iterm-find-highlight[data-iterm-id="${this.instanceId}"], .iterm-find-highlight-current[data-iterm-id="${this.instanceId}"]`);
            const parents = new Set();
            spans.forEach(span => {
                const parent = span.parentNode;
                if (!parent) {
                    return;
                }
                while (span.firstChild) {
                    parent.insertBefore(span.firstChild, span);
                }
                parent.removeChild(span);
                parents.add(parent);
            });

            parents.forEach(p => p.normalize());

            this.globallyAutoOpenedDetails.forEach(d => {
                d.open = false;
            });
            this.globallyAutoOpenedDetails.clear();

            this.revealRestores.forEach(rec => {
                const el = rec.el;
                if (!el) { return; }
                if (rec.type === 'style-display') {
                    el.style.display = rec.oldValue;
                } else if (rec.type === 'style-visibility') {
                    el.style.visibility = rec.oldValue;
                } else if (rec.type === 'attr') {
                    if (rec.oldValue === null || rec.oldValue === '') {
                        el.removeAttribute(rec.attr);
                    } else {
                        el.setAttribute(rec.attr, rec.oldValue);
                    }
                } else if (rec.type === 'class-remove-add') {
                    if (rec.removed) { el.classList.add(rec.removed); }
                }
            });
            this.revealRestores = [];

            this.log('clearHighlights removed spans:', spans.length, 'normalized parents:', parents.size);

            this.highlightedElements = [];
            this.matches = [];
            this.segments = [];
            this.buffer = '';
            this.currentMatchIndex = -1;
            this.hiddenSkippedCount = 0;
        }

        // ---------- Regex ----------
        createSearchRegex(term) {
            let flags = 'g';
            let pattern = term;

            console.debug(TAG, `[${this.instanceId}] createSearchRegex: input term="${term}" mode="${this.searchMode}"`);

            switch (this.searchMode) {
                case 'caseSensitiveRegex': {
                    break;
                }
                case 'caseInsensitiveRegex': {
                    flags += 'i';
                    break;
                }
                case 'caseSensitive': {
                    pattern = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                    break;
                }
                case 'caseInsensitive':
                default: {
                    pattern = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                    flags += 'i';
                    break;
                }
            }

            console.debug(TAG, `[${this.instanceId}] createSearchRegex: final pattern="${pattern}" flags="${flags}"`);

            try {
                const re = new RegExp(pattern, flags);
                console.debug(TAG, `[${this.instanceId}] createSearchRegex: created regex=${re.toString()}`);
                return re;
            } catch (e) {
                console.debug(TAG, `[${this.instanceId}] createSearchRegex: failed, fallback. err=`, e);
                const fallback = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                const re = new RegExp(fallback, flags);
                console.debug(TAG, `[${this.instanceId}] createSearchRegex: fallback regex=${re.toString()}`);
                return re;
            }
        }

        // ---------- Segments ----------
        collectSegments(root) {
            this.segments = [];
            this.buffer = '';
            this.hiddenSkippedCount = 0;

            // Block elements that should introduce visual breaks
            const BLOCK_ELEMENTS = new Set([
                'ADDRESS', 'ARTICLE', 'ASIDE', 'BLOCKQUOTE', 'BR', 'DD', 'DIV',
                'DL', 'DT', 'FIELDSET', 'FIGCAPTION', 'FIGURE', 'FOOTER', 'FORM',
                'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'HEADER', 'HR', 'LI', 'MAIN',
                'NAV', 'OL', 'P', 'PRE', 'SECTION', 'TABLE', 'TD', 'TH', 'TR', 'UL'
            ]);

            const walker = document.createTreeWalker(
                                                     root,
                                                     NodeFilter.SHOW_TEXT,
                                                     {
                                                         acceptNode: (node) => {
                                                             const p = node.parentElement;
                                                             if (!p) { return NodeFilter.FILTER_REJECT; }

                                                             const tag = p.tagName;
                                                             if (tag === 'SCRIPT' || tag === 'STYLE') { return NodeFilter.FILTER_REJECT; }

                                                             if (this.isHidden(p)) {
                                                                 const rev = this.firstRevealableAncestor(p);
                                                                 if (!rev) {
                                                                     this.hiddenSkippedCount++;
                                                                     this.log('reject hidden node', node.textContent.slice(0, 40));
                                                                     return NodeFilter.FILTER_REJECT;
                                                                 } else {
                                                                     node._itermReveal = rev;
                                                                     this.log('accept hidden via revealer', rev.tagName, node.textContent.slice(0, 40));
                                                                 }
                                                             }

                                                             if (!node.textContent || !node.textContent.trim()) {
                                                                 return NodeFilter.FILTER_REJECT;
                                                             }

                                                             return NodeFilter.FILTER_ACCEPT;
                                                         }
                                                     }
                                                     );

            let n;
            let lastNode = null;
            while (n = walker.nextNode()) {
                // Check if we should add a space between this node and the previous one
                if (lastNode && this.hasBlockBoundaryBetween(lastNode, n, BLOCK_ELEMENTS)) {
                    this.buffer += ' ';
                }
                
                const start = this.buffer.length;
                const text = n.textContent;
                this.buffer += text;
                this.segments.push({ node: n, start, length: text.length, revealer: n._itermReveal || null });
                lastNode = n;
            }

            console.debug(TAG, `[${this.instanceId}] collectSegments: buffer="${this.buffer}"`);
            
            this.log('collectSegments done. segments:', this.segments.length, 'buffer length:', this.buffer.length, 'hiddenSkippedCount:', this.hiddenSkippedCount);
        }

        // Check if there's a block boundary between two text nodes in document order
        hasBlockBoundaryBetween(node1, node2, blockElements) {
            // Find the lowest common ancestor of both nodes
            const commonAncestor = this.findCommonAncestor(node1, node2);
            if (!commonAncestor) return false;
            
            // Get the ancestor chains from each node up to the common ancestor
            const path1 = this.getPathToAncestor(node1, commonAncestor);
            const path2 = this.getPathToAncestor(node2, commonAncestor);
            
            // Check if any block element appears in the path from node1 to common ancestor
            // and node2 is not a descendant of that block element
            for (let i = 0; i < path1.length - 1; i++) { // -1 to exclude common ancestor
                const element = path1[i];
                if (blockElements.has(element.tagName)) {
                    // Check if node2 is outside this block element
                    if (!this.isDescendant(node2, element)) {
                        return true;
                    }
                }
            }
            
            // Check the reverse: any block element in path2 that doesn't contain node1
            for (let i = 0; i < path2.length - 1; i++) { // -1 to exclude common ancestor
                const element = path2[i];
                if (blockElements.has(element.tagName)) {
                    // Check if node1 is outside this block element
                    if (!this.isDescendant(node1, element)) {
                        return true;
                    }
                }
            }
            
            return false;
        }
        
        // Find the lowest common ancestor of two nodes
        findCommonAncestor(node1, node2) {
            const ancestors1 = [];
            for (let n = node1; n; n = n.parentElement) {
                ancestors1.push(n);
            }
            
            for (let n = node2; n; n = n.parentElement) {
                if (ancestors1.includes(n)) {
                    return n;
                }
            }
            
            return null;
        }
        
        // Get path from node to ancestor (inclusive)
        getPathToAncestor(node, ancestor) {
            const path = [];
            for (let n = node; n && n !== ancestor; n = n.parentElement) {
                path.push(n);
            }
            if (ancestor) {
                path.push(ancestor);
            }
            return path;
        }
        
        // Check if node is a descendant of ancestor
        isDescendant(node, ancestor) {
            for (let n = node; n; n = n.parentElement) {
                if (n === ancestor) {
                    return true;
                }
            }
            return false;
        }

        // ---------- Search buffer ----------
        findGlobalMatches(regex) {
            console.debug(TAG, `[${this.instanceId}] findGlobalMatches: searching for ${regex.toString()} in buffer of length ${this.buffer.length}`);

            const result = [];
            let m;
            let guard = 0;
            while ((m = regex.exec(this.buffer)) !== null) {
                const match = { start: m.index, end: m.index + m[0].length };
                result.push(match);
                if (m[0].length === 0) { regex.lastIndex++; }
                if (++guard > 1e6) {
                    this.log('findGlobalMatches bail-out: too many iterations');
                    break;
                }
            }
            console.debug(TAG, `[${this.instanceId}] findGlobalMatches: found ${result.length} matches`);
            return result;
        }

        // ---------- Map global -> nodes ----------
        binarySearchSegment(pos) {
            let lo = 0;
            let hi = this.segments.length - 1;
            while (lo <= hi) {
                const mid = (lo + hi) >>> 1;
                const s = this.segments[mid];
                if (pos < s.start) {
                    hi = mid - 1;
                } else if (pos >= s.start + s.length) {
                    lo = mid + 1;
                } else {
                    return mid;
                }
            }
            return lo;
        }

        mapToNodeRanges(globalMatch) {
            const ranges = [];
            let remainingStart = globalMatch.start;
            const remainingEnd = globalMatch.end;

            let i = this.binarySearchSegment(remainingStart);

            while (i < this.segments.length && remainingStart < remainingEnd) {
                const seg = this.segments[i];
                const segEnd = seg.start + seg.length;

                if (segEnd <= remainingStart) {
                    i++;
                    continue;
                }

                const localStart = Math.max(0, remainingStart - seg.start);
                const localEnd = Math.min(seg.length, remainingEnd - seg.start);

                if (localStart < localEnd) {
                    ranges.push({ node: seg.node, startOffset: localStart, endOffset: localEnd, revealer: seg.revealer });
                    remainingStart = seg.start + localEnd;
                } else {
                    remainingStart = segEnd;
                }

                i++;
            }

            return ranges;
        }

        // ---------- Highlight ----------
        highlight(globalMatches) {
            this.matches = [];
            this.log('highlight begin. total global matches:', globalMatches.length);

            for (let i = globalMatches.length - 1; i >= 0; i--) {
                const gm = globalMatches[i];
                const parts = this.mapToNodeRanges(gm);
                const created = [];
                const revs = new Set();

                parts.forEach(part => {
                    try {
                        const r = document.createRange();
                        r.setStart(part.node, part.startOffset);
                        r.setEnd(part.node, part.endOffset);

                        const span = document.createElement('span');
                        span.className = 'iterm-find-highlight';
                        span.setAttribute('data-iterm-id', this.instanceId);
                        r.surroundContents(span);
                        created.push(span);
                        this.highlightedElements.push(span);

                        if (part.revealer) {
                            revs.add(part.revealer);
                        }
                    } catch (e) {
                        this.log('highlight surroundContents failed:', e, 'part:', part);
                    }
                });

                this.matches.unshift({ start: gm.start, end: gm.end, els: created, revealers: revs });
            }

            this.log('highlight done. match objects:', this.matches.length);
        }

        // ---------- Geometry ----------
        updateMatchPositions() {
            this.matches.forEach(m => {
                m.rects = m.els.map(el => el.getBoundingClientRect());
            });
            this.log('updateMatchPositions done.');
        }

        sortMatchesTopToBottom() {
            const curObj = (this.currentMatchIndex >= 0 && this.currentMatchIndex < this.matches.length)
            ? this.matches[this.currentMatchIndex]
            : null;

            this.matches.sort((a, b) => {
                const ra = a.els[0].getBoundingClientRect();
                const rb = b.els[0].getBoundingClientRect();

                if (ra.top !== rb.top) { return ra.top - rb.top; }
                if (ra.left !== rb.left) { return ra.left - rb.left; }
                return a.start - b.start;
            });

            if (curObj) {
                this.currentMatchIndex = this.matches.indexOf(curObj);
            }

            this.log('sortMatchesTopToBottom done. currentMatchIndex:', this.currentMatchIndex);
        }

        // ---------- Auto-reveal ----------
        ensureVisibleForMatch(match) {
            if (!match || !match.els || match.els.length === 0) {
                return;
            }

            const firstEl = match.els[0];
            const needOpen = new Set();

            ancestors(firstEl).forEach(el => {
                if (el.tagName === 'DETAILS' && !el.open) {
                    needOpen.add(el);
                }
            });

            needOpen.forEach(d => {
                d.open = true;
                this.globallyAutoOpenedDetails.add(d);
            });

            if (needOpen.size > 0) {
                this.log('ensureVisibleForMatch auto-opened details (ancestor):', needOpen.size);
            }

            if (match.revealers && match.revealers.size > 0) {
                match.revealers.forEach(el => {
                    this.forceVisible(el);
                    ancestors(el).forEach(ae => {
                        if (this.isHidden(ae)) {
                            this.forceVisible(ae);
                        }
                    });
                });
                this.log('ensureVisibleForMatch processed revealers:', match.revealers.size);
            }

            ancestors(firstEl).forEach(ae => {
                if (this.isHidden(ae)) {
                    this.forceVisible(ae);
                }
            });
        }

        // ---------- Context ----------
        // Returns {contextBefore, contextAfter} for a match or null if contextLen == 0
        getContextsForMatch(match) {
            if (this.contextLen === 0) {
                return null;
            }
            const beforeStart = Math.max(0, match.start - this.contextLen);
            const before = this.buffer.slice(beforeStart, match.start);
            const afterEnd = Math.min(this.buffer.length, match.end + this.contextLen);
            const after = this.buffer.slice(match.end, afterEnd);
            return {
                contextBefore: before,
                contextAfter: after
            };
        }

        // ---------- Report ----------
        reportResults(fullUpdate = false) {
            // For navigation events, only send minimal data
            if (!fullUpdate) {
                const payload = {
                    sessionSecret,
                    action: 'currentChanged',
                    data: {
                        instanceId: this.instanceId,
                        totalMatches: this.matches.length,
                        currentMatch: this.currentMatchIndex + 1,
                        opToken: this.opToken
                    }
                };

                this.log('reportResults (navigation) -> Swift:', {
                    total: this.matches.length,
                    current: this.currentMatchIndex + 1
                });

                try {
                    this.log('reportResults send:', payload);
                    window.webkit?.messageHandlers?.iTermCustomFind?.postMessage(payload);
                } catch (e) {
                    this.log('reportResults postMessage failed:', e);
                }
                return;
            }

            // Full update for new searches
            const matchIdentifiers = [];
            
            this.matches.forEach((m, index) => {
                // Extract the actual matched text from the buffer
                const matchedText = this.buffer.slice(m.start, m.end);
                
                // Create a stable identifier for this match
                const identifier = {
                    index: index,
                    bufferStart: m.start,
                    bufferEnd: m.end,
                    text: matchedText,
                    // Include a content fingerprint for validation
                    // This helps detect if the page content has changed
                    contextFingerprint: this.createContextFingerprint(m)
                };
                matchIdentifiers.push(identifier);
            });

            let contexts = undefined;
            if (this.contextLen > 0) {
                contexts = this.matches.map(m => this.getContextsForMatch(m));
            }

            const payload = {
                sessionSecret,
                action: 'resultsUpdated',
                data: {
                    instanceId: this.instanceId,
                    searchTerm: this.currentSearchTerm,
                    totalMatches: this.matches.length,
                    currentMatch: this.currentMatchIndex + 1,
                    matchIdentifiers: matchIdentifiers,
                    hiddenSkipped: this.hiddenSkippedCount,
                    opToken: this.opToken,
                    contexts: contexts // array of {contextBefore, contextAfter} or undefined
                }
            };

            this.log('reportResults (full) -> Swift:', {
                term: this.currentSearchTerm,
                total: this.matches.length,
                current: this.currentMatchIndex + 1,
                hiddenSkipped: this.hiddenSkippedCount,
                identifiersSample: matchIdentifiers.slice(0, 3),
                contextLen: this.contextLen
            });

            try {
                window.webkit?.messageHandlers?.iTermCustomFind?.postMessage(payload);
            } catch (e) {
                this.log('reportResults postMessage failed:', e);
            }
        }

        // Helper method to create a content fingerprint for match validation
        createContextFingerprint(match) {
            // Use 20 chars before and after for fingerprinting
            const fingerprintRadius = 20;
            const beforeStart = Math.max(0, match.start - fingerprintRadius);
            const afterEnd = Math.min(this.buffer.length, match.end + fingerprintRadius);
            const contextString = this.buffer.slice(beforeStart, afterEnd);
            
            // Simple hash function for the fingerprint
            let hash = 0;
            for (let i = 0; i < contextString.length; i++) {
                const char = contextString.charCodeAt(i);
                hash = ((hash << 5) - hash) + char;
                hash = hash & hash; // Convert to 32-bit integer
            }
            return hash.toString(16);
        }

        // ---------- Navigation ----------
        setCurrent(idx) {
            if (this.matches.length === 0) {
                this.log('setCurrent called but no matches');
                return;
            }

            if (this.currentMatchIndex >= 0 && this.currentMatchIndex < this.matches.length) {
                this.matches[this.currentMatchIndex].els.forEach(e => {
                    e.className = 'iterm-find-highlight';
                    e.setAttribute('data-iterm-id', this.instanceId);
                });
            }

            this.currentMatchIndex = ((idx % this.matches.length) + this.matches.length) % this.matches.length;
            const cur = this.matches[this.currentMatchIndex];

            this.ensureVisibleForMatch(cur);

            cur.els.forEach(e => {
                e.className = 'iterm-find-highlight-current';
                e.setAttribute('data-iterm-id', this.instanceId);
            });

            this.log('setCurrent -> index:', this.currentMatchIndex, 'els:', cur.els.length);

            requestAnimationFrame(() => {
                cur.els[0].scrollIntoView({
                    behavior: 'smooth',
                    block: 'center',
                    inline: 'center'
                });
                this.updateMatchPositions();
                this.reportResults(false); // Navigation update - minimal data
            });
        }

        // ---------- Commands ----------
        startFind(term, mode, contextLen) {
            // bump token so stale async work can be ignored
            this.opToken++;

            console.debug(TAG, `[${this.instanceId}] startFind: searching for "${term}" mode="${mode}" contextLen=${contextLen}`);
            this.log('startFind term:', term, 'mode:', mode, 'contextLen:', contextLen);
            this.clearHighlights();
            this.currentSearchTerm = term;
            this.searchMode = mode || 'substring';
            this.contextLen = Number.isInteger(contextLen) && contextLen > 0 ? contextLen : 0;

            if (!term) {
                this.log('startFind empty term');
                this.reportResults(true); // Full update for cleared search
                return;
            }

            // Check if document.body exists (it won't at documentStart)
            if (!document.body) {
                this.log('startFind: no document.body yet');
                this.reportResults(true); // Full update even if no body
                return;
            }

            document.body.normalize();
            this.log('document.body.normalize() done');

            const regex = this.createSearchRegex(term);
            this.collectSegments(document.body);
            const globalMatches = this.findGlobalMatches(regex);
            this.highlight(globalMatches);
            this.updateMatchPositions();
            this.sortMatchesTopToBottom();
            this.reportResults(true); // Full update for new search

            if (this.matches.length > 0) {
                this.setCurrent(0);
            } else {
                this.log('startFind no matches');
            }
        }

        findNext() {
            this.log('findNext current:', this.currentMatchIndex, 'total:', this.matches.length);
            if (this.matches.length === 0) { return; }
            this.setCurrent(this.currentMatchIndex + 1);
        }

        findPrevious() {
            this.log('findPrevious current:', this.currentMatchIndex, 'total:', this.matches.length);
            if (this.matches.length === 0) { return; }
            this.setCurrent(this.currentMatchIndex - 1);
        }

        // Reveal a specific match by its identifier
        reveal(identifier) {
            if (!identifier) {
                this.log('reveal: no identifier provided');
                return;
            }

            // Find the match by comparing buffer positions and text
            const matchIndex = this.matches.findIndex(m => 
                m.start === identifier.bufferStart && 
                m.end === identifier.bufferEnd &&
                this.buffer.slice(m.start, m.end) === identifier.text
            );

            if (matchIndex === -1) {
                this.log('reveal: match not found for identifier', identifier);
                return;
            }

            this.log('reveal: found match at index', matchIndex);
            
            // Make this the current match and scroll to it
            // setCurrent will handle scrolling and send currentChanged message
            this.setCurrent(matchIndex);
        }

        handleFindCommand(command) {
            this.log('handleFindCommand:', safeStringify(command));
            switch (command.action) {
                case 'startFind': {
                    this.startFind(command.searchTerm,
                                   command.searchMode,
                                   command.contextLength ?? 0);
                    break;
                }
                case 'findNext': {
                    this.findNext();
                    break;
                }
                case 'findPrevious': {
                    this.findPrevious();
                    break;
                }
                case 'clearFind': {
                    this.log('clearFind command');
                    this.clearHighlights();
                    this.currentSearchTerm = '';
                    this.reportResults(true); // Full update for cleared search
                    break;
                }
                case 'updatePositions': {
                    this.log('updatePositions command');
                    if (this.matches.length > 0) {
                        this.updateMatchPositions();
                        this.sortMatchesTopToBottom();
                        // No communication needed - Swift doesn't use positions
                    }
                    break;
                }
                case 'reveal': {
                    this.reveal(command.identifier);
                    break;
                }
                default: {
                    this.log('Unknown action:', command.action);
                    break;
                }
            }
            return {};
        }

        // Get current bounding box for a match using its stable identifier
        // Returns {found: boolean, bounds?: {left, top, right, bottom, width, height}, isCurrent?: boolean}
        getMatchBounds(identifier) {
            if (!identifier) {
                this.log('getMatchBounds: no identifier provided');
                return {};
            }

            // Find the match by comparing buffer positions and text
            const match = this.matches.find(m => 
                m.start === identifier.bufferStart && 
                m.end === identifier.bufferEnd &&
                this.buffer.slice(m.start, m.end) === identifier.text
            );

            if (!match) {
                this.log('getMatchBounds: match not found for identifier', identifier);
                return {};
            }

            // Get bounding boxes for all elements of this match
            const elementBounds = match.els.map(el => el.getBoundingClientRect());
            
            if (elementBounds.length === 0) {
                this.log('getMatchBounds: match has no elements');
                return {};
            }

            // Compute the union bounding box that encompasses all elements
            let left = elementBounds[0].left;
            let top = elementBounds[0].top;
            let right = elementBounds[0].right;
            let bottom = elementBounds[0].bottom;

            for (let i = 1; i < elementBounds.length; i++) {
                const rect = elementBounds[i];
                left = Math.min(left, rect.left);
                top = Math.min(top, rect.top);
                right = Math.max(right, rect.right);
                bottom = Math.max(bottom, rect.bottom);
            }

            const result = {
                x: left,
                y: top,
                width: right - left,
                height: bottom - top
            };

            this.log('getMatchBounds: found match, union of', elementBounds.length, 'elements', result);
            
            return result;
        }

        // ---------- Scroll/Resize ----------
        schedulePositionUpdate() {
            clearTimeout(this.updateTimer);
            this.updateTimer = setTimeout(() => {
                if (this.matches.length > 0) {
                    this.log('scheduled position update');
                    this.updateMatchPositions();
                    this.sortMatchesTopToBottom();
                    // No communication needed - Swift doesn't use positions
                }
            }, 100);
        }

        // ---------- Destroy ----------
        destroy() {
            this.clearHighlights();
            window.removeEventListener('scroll', this.boundScheduleUpdate, true);
            window.removeEventListener('resize', this.boundScheduleUpdate);
            INSTANCES.delete(this.instanceId);
            this.log('Destroyed');
        }
    }

    // ==============================
    //  Public API
    // ==============================
    function getEngine(id) {
        const key = id || DEFAULT_INSTANCE_ID;
        let eng = INSTANCES.get(key);
        if (!eng) {
            eng = new FindEngine(key);
            INSTANCES.set(key, eng);
        }
        return eng;
    }

    function handleCommand(command) {
        const id = command.instanceId || DEFAULT_INSTANCE_ID;
        const eng = getEngine(id);
        return eng.handleFindCommand(command);
    }

    function getMatchBoundsInEngine(instanceId, identifier) {
        const id = instanceId || DEFAULT_INSTANCE_ID;
        const eng = getEngine(id);
        return eng.getMatchBounds(identifier);
    }
    function destroyInstance(id) {
        const eng = INSTANCES.get(id);
        if (eng) {
            eng.destroy();
        }
    }

    // Expose minimal API
    window.iTermCustomFind = {
        handleCommand,
        destroyInstance,
        getMatchBoundsInEngine
    };

    Object.freeze(window.iTermCustomFind);
    console.debug(TAG, 'Initialized multi-instance version');
})();
