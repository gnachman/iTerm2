// Welcome page JavaScript functionality

(function() {
    'use strict';
    
    // Session secret for secure communication
    const sessionSecret = '{{SECRET}}';
    
    // Request top sites when the page loads
    document.addEventListener('DOMContentLoaded', function() {
        loadTopSites();
    });
    
    // Request top sites from Swift
    function loadTopSites() {
        const message = {
            action: 'loadTopSites',
            sessionSecret: sessionSecret
        };
        
        window.webkit.messageHandlers['iterm2-about:welcome'].postMessage(message);
    }
    
    // Handle top sites response from Swift
    window.handleTopSitesResponse = function(sites) {
        const container = document.getElementById('top-sites-list');
        if (!container) return;
        
        container.innerHTML = '';
        
        if (sites.length === 0) {
            container.innerHTML = `
                <div class="empty-state">
                    <span class="empty-icon">🌟</span>
                    <p>Your most visited sites will appear here</p>
                    <p class="empty-hint">Start browsing to build your history!</p>
                </div>
            `;
            return;
        }
        
        sites.forEach(site => {
            const siteCard = createSiteCard(site);
            container.appendChild(siteCard);
        });
    };
    
    // Create a site card element
    function createSiteCard(site) {
        const card = document.createElement('a');
        card.className = 'site-card';
        card.href = site.url;
        
        // Get favicon URL
        const faviconUrl = getFaviconUrl(site.url);
        
        card.innerHTML = `
            <div class="site-favicon">
                <img src="${faviconUrl}" alt="" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
                <div class="site-favicon-fallback" style="display:none;">${getInitial(site.title || site.hostname)}</div>
            </div>
            <div class="site-info">
                <div class="site-title">${escapeHtml(site.title || site.hostname)}</div>
                <div class="site-url">${escapeHtml(site.hostname)}</div>
                <div class="site-visits">${site.visitCount} ${site.visitCount === 1 ? 'visit' : 'visits'}</div>
            </div>
        `;
        
        // Handle navigation through message to Swift
        card.addEventListener('click', function(e) {
            e.preventDefault();
            const message = {
                action: 'navigateToURL',
                url: site.url,
                sessionSecret: sessionSecret
            };
            window.webkit.messageHandlers['iterm2-about:welcome'].postMessage(message);
        });
        
        return card;
    }
    
    // Get favicon URL for a site
    function getFaviconUrl(url) {
        try {
            const urlObj = new URL(url);
            console.debug(`Guessing favicon url of ${urlObj.protocol}//${urlObj.hostname}/favicon.ico`);
            return `${urlObj.protocol}//${urlObj.hostname}/favicon.ico`;
        } catch {
            console.debug(`Can not make a url out of ${url}`);
            return '';
        }
    }
    
    // Get initial letter for fallback icon
    function getInitial(text) {
        return text ? text.charAt(0).toUpperCase() : '?';
    }
    
    // Escape HTML to prevent XSS
    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
    
    // Handle refresh button
    window.refreshTopSites = function() {
        loadTopSites();
    };
})();
