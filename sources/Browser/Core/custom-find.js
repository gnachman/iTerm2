 (function() {
     'use strict';

     const TAG = '[iTermCustomFind]';
     const sessionSecret = "{{SECRET}}";

     // ---------- Styles ----------
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

     // ---------- State ----------
     let currentSearchTerm = '';
     let currentMatchIndex = -1;
     let searchMode = 'caseSensitive';

     let segments = [];      // [{ node: Text, start: number, length: number, revealer: Element|null }]
     let buffer = '';        // concatenated text
     let matches = [];       // [{ start, end, els: HTMLElement[], rects?, revealers?: Set<Element> }]
     let highlightedElements = [];
     let hiddenSkippedCount = 0;

     // details elements we opened automatically for *any* match, so we can close on clear
     const globallyAutoOpenedDetails = new Set();

     // other elements we force-visible; array of restore records
     let revealRestores = [];

     // ---------- Logging ----------
     function log(...args) {
         console.log(TAG, ...args.map(a => (typeof a === 'object' ? safeStringify(a) : a)));
     }

     function safeStringify(obj) {
         try {
             return JSON.stringify(obj);
         } catch (_) {
             return String(obj);
         }
     }

     // ---------- Visibility helpers ----------
     function isHiddenByStyleOrAttr(el) {
         for (let e = el; e; e = e.parentElement) {
             if (e.hasAttribute('hidden')) { return true; }
             if (e.getAttribute('aria-hidden') === 'true') { return true; }
             const cs = getComputedStyle(e);
             if (cs.display === 'none' || cs.visibility === 'hidden') { return true; }
         }
         return false;
     }

     function closedDetailsAncestor(el) {
         for (let e = el; e; e = e.parentElement) {
             if (e.tagName === 'DETAILS' && !e.open) {
                 return e;
             }
         }
         return null;
     }

     const SAFE_REVEAL_SELECTORS = [
         'details:not([open])',
         '.mw-collapsible',
         '.accordion',
         '[aria-expanded="false"]',
         '[data-collapsed="true"]'
     ];

     function firstRevealableAncestor(el) {
         for (let e = el; e; e = e.parentElement) {
             if ( SAFE_REVEAL_SELECTORS.some(sel => { try { return e.matches(sel); } catch (_) { return false; } }) ) {
                 return e;
             }
         }
         return null;
     }

     function isHidden(el) {
         for (let e = el; e; e = e.parentElement) {
             if (e.hasAttribute('hidden')) { return true; }
             if (e.getAttribute('aria-hidden') === 'true') { return true; }
             const cs = getComputedStyle(e);
             if (cs.display === 'none' || cs.visibility === 'hidden') { return true; }
         }
         return false;
     }

     // Force an element visible and record how to undo it.
     function forceVisible(el) {
         try {
             // <details>
             if (el.tagName === 'DETAILS' && !el.open) {
                 el.open = true;
                 globallyAutoOpenedDetails.add(el);
                 return;
             }

             // hidden attribute
             if (el.hasAttribute('hidden')) {
                 revealRestores.push({ el, type: 'attr', attr: 'hidden', oldValue: '' });
                 el.removeAttribute('hidden');
             }

             // aria-hidden
             if (el.getAttribute('aria-hidden') === 'true') {
                 revealRestores.push({ el, type: 'attr', attr: 'aria-hidden', oldValue: 'true' });
                 el.setAttribute('aria-hidden', 'false');
             }

             // CSS display/visibility
             const cs = getComputedStyle(el);
             if (cs.display === 'none') {
                 revealRestores.push({ el, type: 'style-display', oldValue: el.style.display });
                 el.style.display = 'block';
             }
             if (cs.visibility === 'hidden') {
                 revealRestores.push({ el, type: 'style-visibility', oldValue: el.style.visibility });
                 el.style.visibility = 'visible';
             }

             // Common collapse classes/attrs
             if (el.matches('.mw-collapsible')) {
                 if (el.classList.contains('collapsed')) {
                     revealRestores.push({ el, type: 'class-remove-add', removed: 'collapsed' });
                     el.classList.remove('collapsed');
                 }
             }
             if (el.matches('[aria-expanded="false"]')) {
                 revealRestores.push({ el, type: 'attr', attr: 'aria-expanded', oldValue: el.getAttribute('aria-expanded') });
                 el.setAttribute('aria-expanded', 'true');
             }
             if (el.matches('[data-collapsed="true"]')) {
                 revealRestores.push({ el, type: 'attr', attr: 'data-collapsed', oldValue: el.getAttribute('data-collapsed') });
                 el.setAttribute('data-collapsed', 'false');
             }
         } catch (e) {
             log('forceVisible error:', e);
         }
     }

     // ---------- Styles ----------
     function injectStyles() {
         if (document.getElementById('iterm-find-styles')) {
             return;
         }
         const styleElement = document.createElement('style');
         styleElement.id = 'iterm-find-styles';
         styleElement.textContent = highlightStyles;
         document.head.appendChild(styleElement);
         log('Styles injected');
     }

     // ---------- Clear ----------
     function clearHighlights() {
         log('clearHighlights begin');
         const spans = document.querySelectorAll('.iterm-find-highlight, .iterm-find-highlight-current');
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

         // Re-close details we opened
         globallyAutoOpenedDetails.forEach(d => {
             d.open = false;
         });
         globallyAutoOpenedDetails.clear();

         // Revert other forced-visible elements
         revealRestores.forEach(rec => {
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
         revealRestores = [];

         log('clearHighlights removed spans:', spans.length, 'normalized parents:', parents.size);

         highlightedElements = [];
         matches = [];
         segments = [];
         buffer = '';
         currentMatchIndex = -1;
         hiddenSkippedCount = 0;
     }

     // ---------- Regex ----------
     function createSearchRegex(term) {
         let flags = 'g';
         let pattern = term;

         log('createSearchRegex input term:', term, 'mode:', searchMode);

         switch (searchMode) {
             case 'caseSensitiveRegex':
                 // Keep pattern as-is
                 break;
             case 'caseInsensitiveRegex':
                 flags += 'i';
                 break;
             case 'caseSensitive':
                 pattern = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                 break;
             case 'caseInsensitive':
             default:
                 pattern = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                 flags += 'i';
                 break;
         }

         log('createSearchRegex final pattern:', pattern, 'flags:', flags);

         try {
             const re = new RegExp(pattern, flags);
             log('createSearchRegex success:', re.toString());
             return re;
         } catch (e) {
             log('createSearchRegex failed, fallback. err:', e);
             const fallback = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
             const re = new RegExp(fallback, flags);
             log('createSearchRegex fallback regex:', re.toString());
             return re;
         }
     }

     // ---------- Segments ----------
     function collectSegments(root) {
         segments = [];
         buffer = '';
         hiddenSkippedCount = 0;

         const walker = document.createTreeWalker(
             root,
             NodeFilter.SHOW_TEXT,
             {
                 acceptNode(node) {
                     const p = node.parentElement;
                     if (!p) { return NodeFilter.FILTER_REJECT; }

                     const tag = p.tagName;
                     if (tag === 'SCRIPT' || tag === 'STYLE') { return NodeFilter.FILTER_REJECT; }

                     // Handle hidden
                     if (isHidden(p)) {
                         const rev = firstRevealableAncestor(p);
                         if (!rev) {
                             hiddenSkippedCount++;
                             log('reject hidden node', node.textContent.slice(0, 40));
                             return NodeFilter.FILTER_REJECT;
                         } else {
                             node._itermReveal = rev;
                             log('accept hidden via revealer', rev.tagName, node.textContent.slice(0, 40));
                         }
                     }

                     // Empty
                     if (!node.textContent || !node.textContent.trim()) {
                         return NodeFilter.FILTER_REJECT;
                     }

                     return NodeFilter.FILTER_ACCEPT;
                 }
             }
         );

         let n;
         while (n = walker.nextNode()) {
             const start = buffer.length;
             const text = n.textContent;
             buffer += text;
             segments.push({ node: n, start, length: text.length, revealer: n._itermReveal || null });
         }

         log('collectSegments done. segments:', segments.length, 'buffer length:', buffer.length, 'hiddenSkippedCount:', hiddenSkippedCount);
         if (segments.length) {
             log('collectSegments sample segs:', segments.slice(0, 3).map(s => ({
                 start: s.start,
                 length: s.length,
                 textSample: s.node.textContent.slice(0, 40)
             })));
         }
     }

     // ---------- Search buffer ----------
     function findGlobalMatches(regex) {
         const result = [];
         let m;
         let guard = 0;
         while ((m = regex.exec(buffer)) !== null) {
             result.push({ start: m.index, end: m.index + m[0].length });
             if (m[0].length === 0) { regex.lastIndex++; }
             if (++guard > 1e6) {
                 log('findGlobalMatches bail-out: too many iterations');
                 break;
             }
         }
         log('findGlobalMatches found:', result.length);
         if (result.length) {
             log('findGlobalMatches sample:', result.slice(0, 5));
         }
         return result;
     }

     // ---------- Map global -> nodes ----------
     function binarySearchSegment(pos) {
         let lo = 0;
         let hi = segments.length - 1;
         while (lo <= hi) {
             const mid = (lo + hi) >>> 1;
             const s = segments[mid];
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

     function mapToNodeRanges(globalMatch) {
         const ranges = [];
         let remainingStart = globalMatch.start;
         const remainingEnd = globalMatch.end;

         let i = binarySearchSegment(remainingStart);

         while (i < segments.length && remainingStart < remainingEnd) {
             const seg = segments[i];
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
     function highlight(globalMatches) {
         matches = [];
         log('highlight begin. total global matches:', globalMatches.length);

         for (let i = globalMatches.length - 1; i >= 0; i--) {
             const gm = globalMatches[i];
             const parts = mapToNodeRanges(gm);
             const created = [];
             const revs = new Set();

             parts.forEach(part => {
                 try {
                     const r = document.createRange();
                     r.setStart(part.node, part.startOffset);
                     r.setEnd(part.node, part.endOffset);

                     const span = document.createElement('span');
                     span.className = 'iterm-find-highlight';
                     r.surroundContents(span);
                     created.push(span);
                     highlightedElements.push(span);

                     if (part.revealer) {
                         revs.add(part.revealer);
                     }
                 } catch (e) {
                     log('highlight surroundContents failed:', e, 'part:', part);
                 }
             });

             matches.unshift({ start: gm.start, end: gm.end, els: created, revealers: revs });
         }

         log('highlight done. match objects:', matches.length);
     }

     // ---------- Geometry ----------
     function updateMatchPositions() {
         matches.forEach(m => {
             m.rects = m.els.map(el => el.getBoundingClientRect());
         });
         log('updateMatchPositions done.');
     }

     function sortMatchesTopToBottom() {
         // Keep current object so we can restore its index after sort
         const curObj = (currentMatchIndex >= 0 && currentMatchIndex < matches.length)
             ? matches[currentMatchIndex]
             : null;

         matches.sort((a, b) => {
             // Use first span of each match
             const ra = a.els[0].getBoundingClientRect();
             const rb = b.els[0].getBoundingClientRect();

             if (ra.top !== rb.top) { return ra.top - rb.top; }
             if (ra.left !== rb.left) { return ra.left - rb.left; }
             // Tie-breaker: original buffer order
             return a.start - b.start;
         });

         if (curObj) {
             currentMatchIndex = matches.indexOf(curObj);
         }

         log('sortMatchesTopToBottom done. currentMatchIndex:', currentMatchIndex);
     }

     // ---------- Auto-reveal ----------
     function ancestors(el) {
         const arr = [];
         for (let e = el; e; e = e.parentElement) {
             arr.push(e);
         }
         return arr;
     }

     function ensureVisibleForMatch(match) {
         if (!match || !match.els || match.els.length === 0) {
             return;
         }

         // 1. Ancestor details
         const firstEl = match.els[0];
         const needOpen = new Set();

         ancestors(firstEl).forEach(el => {
             if (el.tagName === 'DETAILS' && !el.open) {
                 needOpen.add(el);
             }
         });

         needOpen.forEach(d => {
             d.open = true;
             globallyAutoOpenedDetails.add(d);
         });

         if (needOpen.size > 0) {
             log('ensureVisibleForMatch auto-opened details (ancestor):', needOpen.size);
         }

         // 2. Explicit revealers gathered during segment creation
         if (match.revealers && match.revealers.size > 0) {
             match.revealers.forEach(el => {
                 forceVisible(el);
                 // Also ensure all hidden ancestors above this revealer are fixed
                 ancestors(el).forEach(ae => {
                     if (isHidden(ae)) {
                         forceVisible(ae);
                     }
                 });
             });
             log('ensureVisibleForMatch processed revealers:', match.revealers.size);
         }

         // 3. Finally ensure direct ancestors of the highlight spans are visible
         ancestors(firstEl).forEach(ae => {
             if (isHidden(ae)) {
                 forceVisible(ae);
             }
         });
     }

     // ---------- Report ----------
     function reportResults() {
         const positions = [];
         matches.forEach(m => {
             m.els.forEach(el => {
                 const rect = el.getBoundingClientRect();
                 positions.push({
                     x: rect.left + window.scrollX,
                     y: rect.top + window.scrollY,
                     width: rect.width,
                     height: rect.height
                 });
             });
         });

         positions.sort((a, b) => (a.y - b.y) || (a.x - b.x));

         const payload = {
             sessionSecret,
             action: 'resultsUpdated',
             data: {
                 searchTerm: currentSearchTerm,
                 totalMatches: matches.length,
                 currentMatch: currentMatchIndex + 1,
                 matchPositions: positions,
                 hiddenSkipped: hiddenSkippedCount
             }
         };

         log('reportResults -> Swift:', {
             term: currentSearchTerm,
             total: matches.length,
             current: currentMatchIndex + 1,
             hiddenSkipped: hiddenSkippedCount,
             posSample: positions.slice(0, 3)
         });

         try {
             window.webkit?.messageHandlers?.iTermCustomFind?.postMessage(payload);
         } catch (e) {
             log('reportResults postMessage failed:', e);
         }
     }

     // ---------- Navigation ----------
     function setCurrent(idx) {
         if (matches.length === 0) {
             log('setCurrent called but no matches');
             return;
         }

         if (currentMatchIndex >= 0 && currentMatchIndex < matches.length) {
             matches[currentMatchIndex].els.forEach(e => {
                 e.className = 'iterm-find-highlight';
             });
         }

         currentMatchIndex = ((idx % matches.length) + matches.length) % matches.length;
         const cur = matches[currentMatchIndex];

         ensureVisibleForMatch(cur);

         cur.els.forEach(e => {
             e.className = 'iterm-find-highlight-current';
         });

         log('setCurrent -> index:', currentMatchIndex, 'els:', cur.els.length);

         // Use requestAnimationFrame to scroll after layout settles
         requestAnimationFrame(() => {
             cur.els[0].scrollIntoView({
                 behavior: 'smooth',
                 block: 'center',
                 inline: 'center'
             });
             // After revealing, positions changed
             updateMatchPositions();
             reportResults();
         });
     }

     // ---------- Commands ----------
     function startFind(term, mode) {
         log('startFind term:', term, 'mode:', mode);
         clearHighlights();
         currentSearchTerm = term;
         searchMode = mode || 'substring';

         if (!term) {
             log('startFind empty term');
             reportResults();
             return;
         }

         document.body.normalize();
         log('document.body.normalize() done');

         const regex = createSearchRegex(term);
         collectSegments(document.body);
         const globalMatches = findGlobalMatches(regex);
         highlight(globalMatches);
         updateMatchPositions();
         sortMatchesTopToBottom();
         reportResults();

         if (matches.length > 0) {
             setCurrent(0);
         } else {
             log('startFind no matches');
         }
     }

     function findNext() {
         log('findNext current:', currentMatchIndex, 'total:', matches.length);
         if (matches.length === 0) { return; }
         setCurrent(currentMatchIndex + 1);
     }

     function findPrevious() {
         log('findPrevious current:', currentMatchIndex, 'total:', matches.length);
         if (matches.length === 0) { return; }
         setCurrent(currentMatchIndex - 1);
     }

     function handleFindCommand(command) {
         log('handleFindCommand:', safeStringify(command));
         switch (command.action) {
             case 'startFind':
                 startFind(command.searchTerm, command.searchMode);
                 break;
             case 'findNext':
                 findNext();
                 break;
             case 'findPrevious':
                 findPrevious();
                 break;
             case 'clearFind':
                 log('clearFind command');
                 clearHighlights();
                 currentSearchTerm = '';
                 reportResults();
                 break;
             case 'updatePositions':
                 log('updatePositions command');
                 if (matches.length > 0) {
                     updateMatchPositions();
                     sortMatchesTopToBottom();
                     reportResults();
                 }
                 break;
             default:
                 log('Unknown action:', command.action);
         }
     }

     // ---------- Scroll/Resize ----------
     let updateTimer;
     function schedulePositionUpdate() {
         clearTimeout(updateTimer);
         updateTimer = setTimeout(() => {
             if (matches.length > 0) {
                 log('scheduled position update');
                 updateMatchPositions();
                 sortMatchesTopToBottom();
                 reportResults();
             }
         }, 100);
     }

     // ---------- Init ----------
     injectStyles();

     window.addEventListener('scroll', schedulePositionUpdate, true);
     window.addEventListener('resize', schedulePositionUpdate);

     window.iTermCustomFind = {
         handleCommand: handleFindCommand
     };

     Object.freeze(window.iTermCustomFind);
     log('Initialized');
 })();
