// Common helper functions for distraction removal functionality

function detectMainContainer(article) {
    if (article?.textContent) {
        const words = article.textContent.split(/\s+/).filter(Boolean);
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
    }
    
    // Fallback scoring detection
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
            .reduce((sum, a) => sum + (a.innerText || '').length, 0);
        let s = txt.length * (1 - linkLen / txt.length);
        if (/(article|post|entry|content)/.test(el.id + el.className)) s *= 1.25;
        return s;
    }
    
    const scored = cand.map(el => ({ el, s: score(el) }))
        .sort((a, b) => b.s - a.s);
    return scored[0]?.s > 0 ? scored[0].el : document.body;
}

function findRootOverlay(el, mainContainer) {
    const ancestors = [];
    let curr = el;
    while (curr && curr !== mainContainer && curr !== document.body) {
        ancestors.push(curr);
        curr = curr.parentElement;
    }
    if (!ancestors.length) return el;
    return ancestors.reduce((best, node) => {
        const r = node.getBoundingClientRect();
        const area = r.width * r.height;
        const rb = best.getBoundingClientRect();
        const base = rb.width * rb.height;
        return area > base ? node : best;
    }, el);
}

function findBackdropElements(mainContainer, removed = []) {
    return Array.from(document.body.getElementsByTagName('*')).filter(el => {
        if (removed.includes(el) || el === mainContainer) return false;
        const r = el.getBoundingClientRect();
        const coversX = r.width >= window.innerWidth * 0.9;
        const coversY = r.height >= window.innerHeight * 0.9;
        return coversX && coversY;
    });
}

function injectDistractionRemovalStyles() {
    if (document.getElementById('dr-styles')) return;
    const s = document.createElement('style'); 
    s.id = 'dr-styles';
    s.textContent = `
        body.dr-active { cursor: crosshair !important; }
        .dr-highlight { outline:2px solid #ff4444 !important; opacity:0.5 !important; }
        .dr-removed   { display:none !important; }
    `;
    document.head.appendChild(s);
}

function removeElementAtPoint(clientX, clientY, mainContainer, removed) {
    console.log('[DR] remove element at', clientX, clientY);
    const pts = document.elementsFromPoint(clientX, clientY)
        .filter(x => x !== document.documentElement && x !== document.body);

    let didHide = false;
    for (const el of pts) {
        if (el === mainContainer) break;
        const root = findRootOverlay(el, mainContainer);
        console.log('[DR] hiding root overlay:', root);
        removed.push(root);
        root.classList.add('dr-removed');
        didHide = true;
        break;
    }
    
    if (didHide) {
        // Hide any backdrops that cover the viewport
        const bps = findBackdropElements(mainContainer, removed);
        bps.forEach(bp => {
            console.log('[DR] hiding backdrop via geometry:', bp);
            removed.push(bp);
            bp.classList.add('dr-removed');
        });
    } else {
        console.log('[DR] nothing to hide');
    }
    
    return didHide;
}