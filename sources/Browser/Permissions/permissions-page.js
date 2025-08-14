// Permissions page JavaScript functionality

let currentOffset = 0;
let isLoading = false;
let hasMore = true;
let currentSearchQuery = '';
let currentPermissionTypeFilter = '';
let currentStatusFilter = '';

console.debug("Permissions page loading");

// Initialize permissions page
window.loadPermissions = function(offset = 0, limit = 50, searchQuery = '', permissionTypeFilter = '', statusFilter = '') {
    if (isLoading) return;
    
    isLoading = true;
    showLoadingIndicator();
    
    // Check if message handler is available, retry if not
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers['iterm2-about:permissions']) {
        window.webkit.messageHandlers['iterm2-about:permissions'].postMessage({
            action: 'loadPermissions',
            offset: offset,
            limit: limit,
            searchQuery: searchQuery,
            permissionTypeFilter: permissionTypeFilter,
            statusFilter: statusFilter
        });
    } else {
        console.debug('Message handler not ready, retrying in 50ms...');
        setTimeout(() => {
            isLoading = false;
            loadPermissions(offset, limit, searchQuery, permissionTypeFilter, statusFilter);
        }, 50);
    }
};

window.revokePermission = function(origin, permissionType) {
    if (confirm(`Revoke ${getPermissionDisplayName(permissionType)} permission for ${origin}?`)) {
        window.webkit.messageHandlers['iterm2-about:permissions'].postMessage({
            action: 'revokePermission',
            origin: origin,
            permissionType: permissionType
        });
    }
};

window.revokeAllPermissions = function(origin) {
    if (confirm(`Revoke all permissions for ${origin}? This action cannot be undone.`)) {
        window.webkit.messageHandlers['iterm2-about:permissions'].postMessage({
            action: 'revokeAllPermissions',
            origin: origin
        });
    }
};

window.clearAllPermissions = function() {
    if (confirm('This will revoke all permissions for all websites. This action cannot be undone. Continue?')) {
        window.webkit.messageHandlers['iterm2-about:permissions'].postMessage({
            action: 'clearAllPermissions'
        });
    }
};

// UI Functions
function renderPermissions(permissions) {
    const container = document.getElementById('permissionsContainer');
    
    // Group permissions by origin
    const permissionsByOrigin = groupPermissionsByOrigin(permissions);
    
    Object.keys(permissionsByOrigin).forEach(origin => {
        const originSection = createOriginSection(origin, permissionsByOrigin[origin]);
        container.appendChild(originSection);
    });
    
    // Hide empty state if we have permissions
    if (permissions.length > 0) {
        hideEmptyState();
    }
}

function groupPermissionsByOrigin(permissions) {
    const grouped = {};
    permissions.forEach(permission => {
        if (!grouped[permission.origin]) {
            grouped[permission.origin] = [];
        }
        grouped[permission.origin].push(permission);
    });
    return grouped;
}

function createOriginSection(origin, permissions) {
    const sectionDiv = document.createElement('div');
    sectionDiv.className = 'origin-section';
    sectionDiv.setAttribute('data-origin', origin);
    
    const originHeader = document.createElement('div');
    originHeader.className = 'origin-header';
    originHeader.innerHTML = `
        ${escapeHtml(origin)}
        <div style="margin-left: auto; display: flex; align-items: center; gap: 8px;">
            <button class="button small danger" onclick="revokeAllPermissions('${escapeAttribute(origin)}')" title="Clea all permissions for this site">
                Clear
            </button>
        </div>
    `;
    
    const permissionsList = document.createElement('div');
    permissionsList.className = 'permissions-list';
    
    permissions.forEach(permission => {
        const permissionElement = createPermissionElement(permission);
        permissionsList.appendChild(permissionElement);
    });
    
    sectionDiv.appendChild(originHeader);
    sectionDiv.appendChild(permissionsList);
    
    return sectionDiv;
}

function createPermissionElement(permission) {
    const permissionDiv = document.createElement('div');
    permissionDiv.className = 'permission-entry';
    permissionDiv.setAttribute('data-permission-origin', permission.origin);
    permissionDiv.setAttribute('data-permission-type', permission.permissionType);
    
    const icon = getPermissionIcon(permission.permissionType);
    const displayName = getPermissionDisplayName(permission.permissionType);
    const statusClass = permission.decision === 'granted' ? 'permission-granted' : 'permission-denied';
    const statusText = permission.decision === 'granted' ? 'Allowed' : 'Blocked';
    
    const createdDate = new Date(permission.createdAt * 1000);
    const formattedDate = createdDate.toLocaleDateString([], { 
        year: 'numeric', 
        month: 'short', 
        day: 'numeric' 
    });
    
    permissionDiv.innerHTML = `
        <div class="permission-content">
            <div class="permission-icon">${icon}</div>
            <div class="permission-details">
                <div class="permission-type">${escapeHtml(displayName)}</div>
                <div class="permission-status">
                    <span class="${statusClass}">${statusText}</span>
                    <span class="permission-metadata">• Granted ${formattedDate}</span>
                </div>
            </div>
        </div>
        <div class="permission-actions">
            <button class="revoke-button" onclick="revokePermission('${escapeAttribute(permission.origin)}', '${escapeAttribute(permission.permissionType)}')" title="Revoke this permission">
                ×
            </button>
        </div>
    `;
    
    return permissionDiv;
}

function getPermissionIcon(permissionType) {
    const icons = {
        'notification': '🔔',
        'camera': '📷',
        'microphone': '🎤',
        'cameraAndMicrophone': '📹',
        'geolocation': '📍',
        'audioPlayback': '🔊'
    };
    return icons[permissionType] || '🔒';
}

function getPermissionDisplayName(permissionType) {
    const names = {
        'notification': 'Notifications',
        'camera': 'Camera',
        'microphone': 'Microphone',
        'cameraAndMicrophone': 'Camera and Microphone',
        'geolocation': 'Location',
        'audioPlayback': 'Audio Playback'
    };
    return names[permissionType] || permissionType;
}

function clearPermissionsContainer() {
    const container = document.getElementById('permissionsContainer');
    container.innerHTML = '';
}

function showEmptyState() {
    const container = document.getElementById('permissionsContainer');
    container.innerHTML = `
        <div class="empty-state">
            <div class="empty-icon">🔒</div>
            <h3>No permissions found</h3>
            <p>Website permissions will appear here when you grant them.</p>
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
    
    if (container && button) {
        if (hasMore && currentOffset > 0) {
            container.style.display = 'block';
            button.disabled = false;
        } else {
            container.style.display = 'none';
        }
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

// Search and filter functionality
function performSearch() {
    const searchInput = document.getElementById('searchInput');
    const permissionTypeFilter = document.getElementById('permissionTypeFilter');
    const statusFilter = document.getElementById('statusFilter');
    
    const query = searchInput.value.trim();
    const typeFilter = permissionTypeFilter.value;
    const statusFilterValue = statusFilter.value;
    
    if (query !== currentSearchQuery || 
        typeFilter !== currentPermissionTypeFilter || 
        statusFilterValue !== currentStatusFilter) {
        
        currentSearchQuery = query;
        currentPermissionTypeFilter = typeFilter;
        currentStatusFilter = statusFilterValue;
        currentOffset = 0;
        hasMore = true;
        
        clearPermissionsContainer();
        loadPermissions(0, 50, query, typeFilter, statusFilterValue);
    }
}

function clearSearch() {
    const searchInput = document.getElementById('searchInput');
    const permissionTypeFilter = document.getElementById('permissionTypeFilter');
    const statusFilter = document.getElementById('statusFilter');
    
    searchInput.value = '';
    permissionTypeFilter.value = '';
    statusFilter.value = '';
    
    currentSearchQuery = '';
    currentPermissionTypeFilter = '';
    currentStatusFilter = '';
    currentOffset = 0;
    hasMore = true;
    
    clearPermissionsContainer();
    loadPermissions(0, 50, '', '', '');
}

function loadMore() {
    if (hasMore && !isLoading) {
        loadPermissions(currentOffset, 50, currentSearchQuery, currentPermissionTypeFilter, currentStatusFilter);
    }
}

// Callback functions for receiving data from Swift
window.onPermissionsLoaded = function(data) {
    isLoading = false;
    hideLoadingIndicator();
    
    const { permissions, hasMore: moreAvailable } = data;
    hasMore = moreAvailable;
    
    if (currentOffset === 0) {
        // Clear existing permissions for new search or initial load
        clearPermissionsContainer();
    }
    
    if (permissions.length === 0 && currentOffset === 0) {
        showEmptyState();
    } else {
        renderPermissions(permissions);
    }
    
    currentOffset += permissions.length;
    updateLoadMoreButton();
};

window.onPermissionRevoked = function(origin, permissionType) {
    // Find and remove the specific permission entry
    const permissionElement = document.querySelector(`[data-permission-origin="${escapeAttribute(origin)}"][data-permission-type="${escapeAttribute(permissionType)}"]`);
    if (permissionElement) {
        permissionElement.remove();
        
        // Check if this was the last permission for this origin
        const originSection = document.querySelector(`[data-origin="${escapeAttribute(origin)}"]`);
        if (originSection) {
            const permissionsList = originSection.querySelector('.permissions-list');
            if (permissionsList && permissionsList.children.length === 0) {
                originSection.remove();
            }
        }
        
        // Check if container is now empty
        const container = document.getElementById('permissionsContainer');
        if (container.children.length === 0) {
            showEmptyState();
        }
    }
    
    showStatus('Permission revoked', 'success');
};

window.onAllPermissionsRevoked = function(origin) {
    // Remove the entire origin section
    const originSection = document.querySelector(`[data-origin="${escapeAttribute(origin)}"]`);
    if (originSection) {
        originSection.remove();
        
        // Check if container is now empty
        const container = document.getElementById('permissionsContainer');
        if (container.children.length === 0) {
            showEmptyState();
        }
    }
    
    showStatus(`All permissions revoked for ${origin}`, 'success');
};

window.onAllPermissionsCleared = function() {
    clearPermissionsContainer();
    currentOffset = 0;
    hasMore = true;
    showStatus('All permissions cleared', 'success');
    showEmptyState();
};

// Initialize page when loaded
window.addEventListener('load', function() {
    // Set document title explicitly for custom URL scheme
    document.title = 'Site Permissions';
    
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
    
    // Setup filter selectors
    const permissionTypeFilter = document.getElementById('permissionTypeFilter');
    if (permissionTypeFilter) {
        permissionTypeFilter.addEventListener('change', performSearch);
    }
    
    const statusFilter = document.getElementById('statusFilter');
    if (statusFilter) {
        statusFilter.addEventListener('change', performSearch);
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
    loadPermissions(0, 50, '', '', '');
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
