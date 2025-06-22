// Bookmarks page JavaScript functionality

let currentOffset = 0;
let isLoading = false;
let hasMore = true;
let currentSearchQuery = '';
let currentSortBy = 'dateAdded';
let activeTags = [];
let allTags = [];

console.log("Bookmarks page loading");

// Initialize bookmarks page
window.loadBookmarks = function(offset = 0, limit = 50, searchQuery = '', sortBy = 'dateAdded', tags = []) {
    if (isLoading) return;
    
    isLoading = true;
    showLoadingIndicator();
    
    // Check if message handler is available, retry if not
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers['iterm2-about:bookmarks']) {
        window.webkit.messageHandlers['iterm2-about:bookmarks'].postMessage({
            action: 'loadBookmarks',
            offset: offset,
            limit: limit,
            searchQuery: searchQuery,
            sortBy: sortBy,
            tags: tags
        });
    } else {
        console.log('Message handler not ready, retrying in 50ms...');
        setTimeout(() => {
            isLoading = false;
            loadBookmarks(offset, limit, searchQuery, sortBy, tags);
        }, 50);
    }
};

window.deleteBookmark = function(url) {
    if (confirm('Delete this bookmark?')) {
        window.webkit.messageHandlers['iterm2-about:bookmarks'].postMessage({
            action: 'deleteBookmark',
            url: url
        });
    }
};

window.navigateToURL = function(url) {
    window.webkit.messageHandlers['iterm2-about:bookmarks'].postMessage({
        action: 'navigateToURL',
        url: url
    });
};

window.clearAllBookmarks = function() {
    if (confirm('This will delete all bookmarks. This action cannot be undone. Continue?')) {
        window.webkit.messageHandlers['iterm2-about:bookmarks'].postMessage({
            action: 'clearAllBookmarks'
        });
    }
};

window.loadTags = function() {
    // Check if message handler is available, retry if not
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers['iterm2-about:bookmarks']) {
        window.webkit.messageHandlers['iterm2-about:bookmarks'].postMessage({
            action: 'loadTags'
        });
    } else {
        console.log('Message handler not ready for tags, retrying in 50ms...');
        setTimeout(() => {
            loadTags();
        }, 50);
    }
};

// Callback functions moved to top of file

// UI Functions
function renderBookmarks(bookmarks) {
    const container = document.getElementById('bookmarksContainer');
    
    bookmarks.forEach(bookmark => {
        const bookmarkElement = createBookmarkElement(bookmark);
        container.appendChild(bookmarkElement);
    });
    
    // Hide empty state if we have bookmarks
    if (bookmarks.length > 0) {
        hideEmptyState();
    }
}

function createBookmarkElement(bookmark) {
    const bookmarkDiv = document.createElement('div');
    bookmarkDiv.className = 'bookmark-entry';
    bookmarkDiv.setAttribute('data-bookmark-url', bookmark.url);
    
    const title = bookmark.title || 'Untitled';
    const url = bookmark.url;
    const dateAdded = new Date(bookmark.dateAdded * 1000);
    const formattedDate = dateAdded.toLocaleDateString([], { 
        year: 'numeric', 
        month: 'short', 
        day: 'numeric' 
    });
    
    // Tags HTML
    const tagsHtml = bookmark.tags ? 
        bookmark.tags.map(tag => `<span class="bookmark-tag">${escapeHtml(tag)}</span>`).join('') : '';
    
    bookmarkDiv.innerHTML = `
        <div class="entry-content">
            <div class="entry-header">
                <span class="entry-date">Added ${formattedDate}</span>
                <div class="entry-title">${escapeHtml(title)}</div>
            </div>
            <div class="entry-url" onclick="navigateToURL('${escapeAttribute(url)}')" title="Click to navigate to this URL">
                ${escapeHtml(url)}
            </div>
            ${tagsHtml ? `<div class="bookmark-meta"><div class="bookmark-tags">${tagsHtml}</div></div>` : ''}
        </div>
        <div class="entry-actions">
            <button class="delete-button" onclick="deleteBookmark('${escapeAttribute(url)}')" title="Delete this bookmark">
                <span class="delete-icon">×</span>
            </button>
        </div>
    `;
    
    return bookmarkDiv;
}

function renderTags() {
    const tagsList = document.getElementById('tagsList');
    tagsList.innerHTML = '';
    
    allTags.forEach(tag => {
        const tagElement = document.createElement('div');
        tagElement.className = 'tag-filter';
        tagElement.textContent = tag;
        tagElement.onclick = () => toggleTag(tag);
        
        if (activeTags.includes(tag)) {
            tagElement.classList.add('active');
        }
        
        tagsList.appendChild(tagElement);
    });
}

function toggleTag(tag) {
    if (activeTags.includes(tag)) {
        activeTags = activeTags.filter(t => t !== tag);
    } else {
        activeTags.push(tag);
    }
    
    updateTagFilters();
    performSearch();
}

function updateTagFilters() {
    const tagElements = document.querySelectorAll('.tag-filter');
    tagElements.forEach(element => {
        const tag = element.textContent;
        if (activeTags.includes(tag)) {
            element.classList.add('active');
        } else {
            element.classList.remove('active');
        }
    });
}

function clearBookmarksContainer() {
    const container = document.getElementById('bookmarksContainer');
    container.innerHTML = '';
}

function showEmptyState() {
    const container = document.getElementById('bookmarksContainer');
    container.innerHTML = `
        <div class="empty-state">
            <div class="empty-icon">📚</div>
            <h3>No bookmarks found</h3>
            <p>Start bookmarking your favorite websites to see them here.</p>
        </div>
    `;
}

function hideEmptyState() {
    const emptyState = document.querySelector('.empty-state');
    if (emptyState) {
        emptyState.remove();
    }
}

function showLoadingIndicator() {
    const indicator = document.getElementById('loadingIndicator');
    if (indicator) {
        indicator.style.display = 'block';
    }
}

function hideLoadingIndicator() {
    const indicator = document.getElementById('loadingIndicator');
    if (indicator) {
        indicator.style.display = 'none';
    }
}

function updateLoadMoreButton() {
    const container = document.getElementById('loadMoreContainer');
    const button = document.getElementById('loadMoreButton');
    
    if (hasMore && currentOffset > 0) {
        container.style.display = 'block';
        button.disabled = false;
    } else {
        container.style.display = 'none';
    }
}

function showStatus(message, type = 'info', duration = 3000) {
    // Create status element if it doesn't exist
    let statusElement = document.getElementById('statusMessage');
    if (!statusElement) {
        statusElement = document.createElement('div');
        statusElement.id = 'statusMessage';
        statusElement.className = 'status-message';
        document.body.appendChild(statusElement);
    }
    
    statusElement.textContent = message;
    statusElement.className = `status-message ${type} show`;
    
    // Auto-hide after duration
    if (duration > 0) {
        setTimeout(() => {
            statusElement.classList.remove('show');
        }, duration);
    }
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function escapeAttribute(text) {
    return text.replace(/'/g, "&#39;").replace(/"/g, "&#34;");
}

// Search functionality
function performSearch() {
    const searchInput = document.getElementById('searchInput');
    const sortSelect = document.getElementById('sortSelect');
    
    const query = searchInput.value.trim();
    const sortBy = sortSelect.value;
    
    if (query !== currentSearchQuery || sortBy !== currentSortBy || activeTags.length > 0) {
        currentSearchQuery = query;
        currentSortBy = sortBy;
        currentOffset = 0;
        hasMore = true;
        loadBookmarks(0, 50, query, sortBy, activeTags);
    }
}

function clearSearch() {
    const searchInput = document.getElementById('searchInput');
    searchInput.value = '';
    currentSearchQuery = '';
    activeTags = [];
    updateTagFilters();
    currentOffset = 0;
    hasMore = true;
    loadBookmarks(0, 50, '', currentSortBy, []);
}

function loadMore() {
    if (hasMore && !isLoading) {
        loadBookmarks(currentOffset, 50, currentSearchQuery, currentSortBy, activeTags);
    }
}

// Ensure all callback functions are defined first
window.onBookmarksLoaded = function(data) {
    isLoading = false;
    hideLoadingIndicator();
    
    const { bookmarks, hasMore: moreAvailable } = data;
    hasMore = moreAvailable;
    
    if (currentOffset === 0) {
        // Clear existing bookmarks for new search or initial load
        clearBookmarksContainer();
    }
    
    renderBookmarks(bookmarks);
    currentOffset += bookmarks.length;
    
    updateLoadMoreButton();
};

window.onTagsLoaded = function(data) {
    const { tags } = data;
    allTags = tags;
    renderTags();
};

window.onBookmarkDeleted = function(url) {
    const bookmarkElement = document.querySelector(`[data-bookmark-url="${escapeAttribute(url)}"]`);
    if (bookmarkElement) {
        bookmarkElement.remove();
        
        // Check if container is now empty
        const container = document.getElementById('bookmarksContainer');
        if (container.children.length === 0) {
            showEmptyState();
        }
    }
    
    showStatus('Bookmark deleted', 'success');
};

window.onBookmarksCleared = function() {
    clearBookmarksContainer();
    currentOffset = 0;
    hasMore = true;
    activeTags = [];
    updateTagFilters();
    showStatus('All bookmarks cleared', 'success');
    showEmptyState();
};

// Initialize page when loaded
window.addEventListener('load', function() {
    // Set document title explicitly for custom URL scheme
    document.title = 'Bookmarks';
    // Setup search input
    const searchInput = document.getElementById('searchInput');
    if (searchInput) {
        searchInput.addEventListener('input', debounce(performSearch, 300));
        searchInput.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') {
                performSearch();
            } else if (e.key === 'Escape') {
                clearSearch();
            }
        });
    }
    
    // Setup sort selector
    const sortSelect = document.getElementById('sortSelect');
    if (sortSelect) {
        sortSelect.addEventListener('change', performSearch);
    }
    
    // Setup clear all button
    const clearAllButton = document.getElementById('clearAllButton');
    if (clearAllButton) {
        clearAllButton.addEventListener('click', clearAllBookmarks);
    }
    
    // Setup load more button
    const loadMoreButton = document.getElementById('loadMoreButton');
    if (loadMoreButton) {
        loadMoreButton.addEventListener('click', loadMore);
    }
    
    // Setup infinite scrolling
    window.addEventListener('scroll', function() {
        if ((window.innerHeight + window.scrollY) >= document.body.offsetHeight - 1000) {
            loadMore();
        }
    });
    
    // Load initial data
    loadTags();
    loadBookmarks(0, 50, '', 'dateAdded', []);
});

// Utility function for debouncing search
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}
