// Distraction Removal functionality for iTerm2 Browser (v10)
(function() {
  'use strict';

  let isActive = false;
  let mainContainer = null;
  let removed = [];
  let captureLayer = null;

  function enter() {
    console.log('[DR] enter()');
    if (typeof Readability === 'undefined') {
      console.error('[DR] Readability.js missing');
      return false;
    }

    const docClone = document.cloneNode(true);
    const reader   = new Readability(docClone);
    const article  = reader.parse();
    console.log('[DR] Readability.parse →', article);

    mainContainer = detectMainContainer(article);
    console.log('[DR] mainContainer →', mainContainer);

    // capture layer above all content
    captureLayer = document.createElement('div');
    Object.assign(captureLayer.style, {
      position:   'fixed',
      top:        '0',
      left:       '0',
      width:      '100vw',
      height:     '100vh',
      zIndex:     '2147483647',
      background: 'transparent',
      cursor:     'crosshair'
    });
    document.body.appendChild(captureLayer);

    captureLayer.addEventListener('mousemove', onMove, { passive: true });
    captureLayer.addEventListener('click',     onClick, true);

    injectStyles();
    document.body.classList.add('dr-active');
    isActive = true;
    return true;
  }

  function exit() {
    console.log('[DR] exit()');
    if (!isActive) return false;

    captureLayer.removeEventListener('mousemove', onMove);
    captureLayer.removeEventListener('click',     onClick, true);
    captureLayer.remove();
    captureLayer = null;

    document.querySelectorAll('.dr-highlight')
            .forEach(el => el.classList.remove('dr-highlight'));
    document.body.classList.remove('dr-active');
    isActive = false;
    // Notify native
    if (window.webkit?.messageHandlers?.readerMode) {
      window.webkit.messageHandlers.readerMode.postMessage({ action: 'distractionRemovalExited' });
    }
    return true;
  }

  document.addEventListener('keydown', e => {
    if (!e.isTrusted) return;
    if (e.key === 'Escape' && isActive) exit();
  });

  function detectMainContainer(article) {
    if (article?.textContent) {
      const words = article.textContent.split(/\s+/).filter(Boolean);
        console.log(`Text contetn of article has length ${words.length}: ${article.textContent}`);
      if (words.length >= 20) {
        const sample = words.slice(0, 20).join(' ');
        const candidates = Array.from(
          document.querySelectorAll('article, main, div, section, [role=main]')
        );
        const matches = candidates.filter(el => el.innerText.includes(sample));
        if (matches.length) {
          return matches.reduce((best, el) =>
            el.innerText.length > best.innerText.length ? el : best,
            matches[0]
          );
        }
      }
    } else {
        console.log("No article or no text content");
    }
    console.log('[DR] fallback scoring detection');
    const cand = Array.from(
      document.querySelectorAll('article, main, div, section, [role=main]')
    ).filter(el => {
      const t = el.tagName.toLowerCase();
      const h = (el.id + ' ' + el.className).toLowerCase();
      return !/(nav|aside|header|footer|form)/.test(t)
          && !/(sidebar|advert|promo|widget|menu|comment)/.test(h);
    });
    function score(el) {
      const txt = el.innerText || '';
      if (txt.length < 200) return 0;
      const linkLen = Array.from(el.querySelectorAll('a'))
        .reduce((sum,a)=> sum + (a.innerText||'').length, 0);
      let s = txt.length * (1 - linkLen/txt.length);
      if (/(article|post|entry|content)/.test(el.id + el.className)) s*=1.25;
      return s;
    }
    const scored = cand.map(el=>({el,s:score(el)}))
                      .sort((a,b)=>b.s-a.s);
    console.log('[DR] scored top:', scored[0]);
    return scored[0]?.s>0? scored[0].el : document.body;
  }

  function findRootOverlay(el) {
    const ancestors = [];
    let curr = el;
    while (curr && curr !== mainContainer && curr !== document.body) {
      ancestors.push(curr);
      curr = curr.parentElement;
    }
    if (!ancestors.length) return el;
    return ancestors.reduce((best,node) => {
      const r = node.getBoundingClientRect();
      const area = r.width * r.height;
      const rb = best.getBoundingClientRect();
      const base = rb.width * rb.height;
      return area > base ? node : best;
    }, el);
  }

  function findBackdropElements() {
    return Array.from(document.body.getElementsByTagName('*')).filter(el => {
      if (removed.includes(el) || el === captureLayer || el === mainContainer) return false;
      const r = el.getBoundingClientRect();
      const coversX = r.width >= window.innerWidth * 0.9;
      const coversY = r.height >= window.innerHeight * 0.9;
      return coversX && coversY;
    });
  }

  function onMove(e) {
    const pts = document.elementsFromPoint(e.clientX,e.clientY)
      .filter(x=>x!==captureLayer && x!==document.documentElement && x!==document.body);
    document.querySelectorAll('.dr-highlight')
            .forEach(el=>el.classList.remove('dr-highlight'));
    if (!pts.length) return;
    const root = findRootOverlay(pts[0]);
    if (root!==mainContainer && !mainContainer.contains(root)) {
      root.classList.add('dr-highlight');
    }
  }

  function onClick(e) {
    console.log('[DR] click at', e.clientX, e.clientY);
    const pts = document.elementsFromPoint(e.clientX,e.clientY)
      .filter(x=>x!==captureLayer && x!==document.documentElement && x!==document.body);

    let didHide = false;
    for (const el of pts) {
      if (el===mainContainer) break;
      const root = findRootOverlay(el);
      console.log('[DR] hiding root overlay:', root);
      removed.push(root);
      root.classList.add('dr-removed');
      didHide = true;
      break;
    }
    if (didHide) {
      // hide any backdrops that cover the viewport
      const bps = findBackdropElements();
      bps.forEach(bp => {
        console.log('[DR] hiding backdrop via geometry:', bp);
        removed.push(bp);
        bp.classList.add('dr-removed');
      });
    }
    if (didHide) {
      e.preventDefault(); e.stopPropagation();
    } else {
      console.log('[DR] nothing to hide');
    }
  }

  function injectStyles() {
    if (document.getElementById('dr-styles')) return;
    const s = document.createElement('style'); s.id = 'dr-styles';
    s.textContent = `
      body.dr-active { cursor: crosshair !important; }
      .dr-highlight { outline:2px solid #ff4444 !important; opacity:0.5 !important; }
      .dr-removed   { display:none !important; }
    `;
    document.head.appendChild(s);
  }

  window.iTermDistractionRemoval = { enter, exit, isActive: ()=>isActive };

  return true;
})();
