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
    let adContainer = null;
    
    // Walk up the tree, looking for ad-related containers
    while (curr && curr !== mainContainer && curr !== document.body) {
        ancestors.push(curr);
        
        // Check if this is an ad-related container
        const classes = curr.className || '';
        const id = curr.id || '';
        const combined = (classes + ' ' + id).toLowerCase();
        
        if (/(^|\s)(ad|advertisement|banner|popup|modal|overlay|sidebar|widget|promo)(\s|$)/.test(combined) ||
            /(adsby|display_ad|ad_place|advert)/.test(combined)) {
            // Found an ad container - now walk up until we find a significantly larger parent
            adContainer = curr;
            let parent = curr.parentElement;
            
            while (parent && parent !== mainContainer && parent !== document.body) {
                const currRect = adContainer.getBoundingClientRect();
                const parentRect = parent.getBoundingClientRect();
                const currArea = currRect.width * currRect.height;
                const parentArea = parentRect.width * parentRect.height;
                
                // If parent is significantly larger (>10% bigger), stop at current
                if (parentArea > currArea * 1.1) {
                    break;
                }
                
                // Parent is similar size, keep walking up
                adContainer = parent;
                parent = parent.parentElement;
            }
            
            return adContainer;
        }
        
        curr = curr.parentElement;
    }
    
    if (!ancestors.length) return el;
    
    // Return the largest element if no ad container was found
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

function removeElementAtPoint(clientX, clientY, mainContainer, removed, skipBackdrops = false) {
    console.debug('[DR] remove element at', clientX, clientY);
    const pts = document.elementsFromPoint(clientX, clientY)
        .filter(x => x !== document.documentElement && x !== document.body);

    let didHide = false;
    for (const el of pts) {
        if (el === mainContainer) break;
        const root = findRootOverlay(el, mainContainer);
        
        // Check if already removed
        if (root.classList.contains('dr-removed')) {
            console.debug('[DR] element already removed:', root);
            break;
        }
        
        const rect = root.getBoundingClientRect();
        console.debug('[DR] hiding root overlay:', root);
        console.debug('[DR] root overlay bounds:', `x=${rect.x}, y=${rect.y}, width=${rect.width}, height=${rect.height}`);
        
        // More aggressive removal for stubborn ads
        root.classList.add('dr-removed');
        root.style.display = 'none';
        root.style.visibility = 'hidden';
        root.style.opacity = '0';
        root.style.height = '0';
        root.style.width = '0';
        root.style.overflow = 'hidden';
        
        removed.push(root);
        didHide = true;
        break;
    }
    
    if (didHide && !skipBackdrops) {
        // Hide any backdrops that cover the viewport (only in full distraction removal mode)
        const bps = findBackdropElements(mainContainer, removed);
        bps.forEach(bp => {
            console.debug('[DR] hiding backdrop via geometry:', bp);
            removed.push(bp);
            bp.classList.add('dr-removed');
        });
    } else if (!didHide) {
        console.debug('[DR] nothing to hide');
    }
    
    return didHide;
}
