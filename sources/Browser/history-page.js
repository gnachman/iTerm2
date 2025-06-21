// History page JavaScript functionality

let currentOffset = 0;
let isLoading = false;
let hasMore = true;
let currentSearchQuery = '';

// Initialize history page
window.loadHistoryEntries = function(offset = 0, limit = 50, searchQuery = '') {
    if (isLoading) return;
    
    isLoading = true;
    showLoadingIndicator();
    
    window.webkit.messageHandlers.iterm2BrowserHistory.postMessage({
        action: 'loadEntries',
        offset: offset,
        limit: limit,
        searchQuery: searchQuery
    });
};

window.deleteHistoryEntry = function(entryId) {
    if (confirm('Delete this history entry?')) {
        window.webkit.messageHandlers.iterm2BrowserHistory.postMessage({
            action: 'deleteEntry',
            entryId: entryId
        });
    }
};

window.navigateToURL = function(url) {
    window.webkit.messageHandlers.iterm2BrowserHistory.postMessage({
        action: 'navigateToURL',
        url: url
    });
};

window.clearAllHistory = function() {
    if (confirm('This will delete all browsing history. This action cannot be undone. Continue?')) {
        window.webkit.messageHandlers.iterm2BrowserHistory.postMessage({
            action: 'clearAllHistory'
        });
    }
};

// Callback functions called from Swift
window.onHistoryEntriesLoaded = function(data) {
    isLoading = false;
    hideLoadingIndicator();
    
    const { entries, hasMore: moreAvailable } = data;
    hasMore = moreAvailable;
    
    if (currentOffset === 0) {
        // Clear existing entries for new search or initial load
        clearHistoryContainer();
    }
    
    renderHistoryEntries(entries);
    currentOffset += entries.length;
    
    updateLoadMoreButton();
};

window.onHistoryEntryDeleted = function(entryId) {
    const entryElement = document.querySelector(`[data-entry-id="${entryId}"]`);
    if (entryElement) {
        entryElement.remove();
        
        // Check if we removed the last entry in a date section
        const section = entryElement.closest('.date-section');
        if (section && section.querySelectorAll('.history-entry').length === 0) {
            section.remove();
        }
    }
    
    showStatus('History entry deleted', 'success');
};

window.onHistoryCleared = function() {
    clearHistoryContainer();
    currentOffset = 0;
    hasMore = true;
    showStatus('All history cleared', 'success');
    
    // Show empty state
    showEmptyState();
};

// UI Functions
function renderHistoryEntries(entries) {
    const container = document.getElementById('historyContainer');
    let currentDateSection = null;
    let lastFormattedDate = null;
    
    entries.forEach(entry => {
        const entryDate = new Date(entry.visitDate * 1000);
        const dateString = entryDate.toLocaleDateString();
        const formattedDateHeader = formatDateHeader(dateString);
        
        // Create new date section if needed
        if (formattedDateHeader !== lastFormattedDate) {
            // First check if a section for this date already exists in the DOM
            const existingSection = findExistingDateSection(formattedDateHeader);
            
            if (existingSection) {
                currentDateSection = existingSection;
            } else {
                currentDateSection = createDateSection(dateString);
                container.appendChild(currentDateSection);
            }
            lastFormattedDate = formattedDateHeader;
        }
        
        // Create and append entry
        const entryElement = createHistoryEntryElement(entry, entryDate);
        currentDateSection.querySelector('.entries-list').appendChild(entryElement);
    });
    
    // Hide empty state if we have entries
    if (entries.length > 0) {
        hideEmptyState();
    }
}

function createDateSection(dateString) {
    const section = document.createElement('div');
    section.className = 'date-section';
    
    const header = document.createElement('h3');
    header.className = 'date-header';
    header.textContent = formatDateHeader(dateString);
    
    const entriesList = document.createElement('div');
    entriesList.className = 'entries-list';
    
    section.appendChild(header);
    section.appendChild(entriesList);
    
    return section;
}

function findExistingDateSection(formattedDateHeader) {
    const container = document.getElementById('historyContainer');
    const existingHeaders = container.querySelectorAll('.date-header');
    
    for (const header of existingHeaders) {
        if (header.textContent === formattedDateHeader) {
            return header.closest('.date-section');
        }
    }
    
    return null;
}

function createHistoryEntryElement(entry, date) {
    const entryDiv = document.createElement('div');
    entryDiv.className = 'history-entry';
    entryDiv.setAttribute('data-entry-id', entry.id);
    
    const timeString = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const title = entry.title || 'Untitled';
    const url = entry.url;
    
    entryDiv.innerHTML = `
        <div class="entry-content">
            <div class="entry-header">
                <span class="entry-time">${timeString}</span>
                <span class="entry-title">${escapeHtml(title)}</span>
            </div>
            <div class="entry-url" onclick="navigateToURL('${escapeHtml(url)}')" title="Click to navigate to this URL">
                ${escapeHtml(url)}
            </div>
        </div>
        <div class="entry-actions">
            <button class="delete-button" onclick="deleteHistoryEntry('${entry.id}')" title="Delete this entry">
                <span class="delete-icon">×</span>
            </button>
        </div>
    `;
    
    return entryDiv;
}

function formatDateHeader(dateString) {
    const date = new Date(dateString);
    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    
    if (date.toDateString() === today.toDateString()) {
        return 'Today';
    } else if (date.toDateString() === yesterday.toDateString()) {
        return 'Yesterday';
    } else {
        return date.toLocaleDateString([], { 
            weekday: 'long', 
            year: 'numeric', 
            month: 'long', 
            day: 'numeric' 
        });
    }
}

function clearHistoryContainer() {
    const container = document.getElementById('historyContainer');
    container.innerHTML = '';
}

function showEmptyState() {
    const container = document.getElementById('historyContainer');
    container.innerHTML = `
        <div class="empty-state">
            <div class="empty-icon">📚</div>
            <h3>No browsing history</h3>
            <p>Your browsing history will appear here as you visit websites.</p>
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
    const button = document.getElementById('loadMoreButton');
    if (button) {
        button.style.display = hasMore ? 'block' : 'none';
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

// Search functionality
function performSearch() {
    const searchInput = document.getElementById('searchInput');
    const query = searchInput.value.trim();
    
    if (query !== currentSearchQuery) {
        currentSearchQuery = query;
        currentOffset = 0;
        hasMore = true;
        loadHistoryEntries(0, 50, query);
    }
}

function clearSearch() {
    const searchInput = document.getElementById('searchInput');
    searchInput.value = '';
    currentSearchQuery = '';
    currentOffset = 0;
    hasMore = true;
    loadHistoryEntries(0, 50, '');
}

function loadMore() {
    if (hasMore && !isLoading) {
        loadHistoryEntries(currentOffset, 50, currentSearchQuery);
    }
}

// Initialize page when loaded
window.addEventListener('load', function() {
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
    
    // Setup infinite scrolling
    window.addEventListener('scroll', function() {
        if ((window.innerHeight + window.scrollY) >= document.body.offsetHeight - 1000) {
            loadMore();
        }
    });
    
    // Load initial entries
    loadHistoryEntries(0, 50, '');
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