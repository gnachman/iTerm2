// Background service worker for Custom User Agent extension

// Track which tabs should have modified User-Agent
const modifiedTabs = new Set();

// Listen for tab updates
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  // When tab finishes loading, check if it's a target domain
  if (changeInfo.status === 'complete' && tab.url) {
    const url = new URL(tab.url);
    
    if (url.hostname === 'example.com' || url.hostname === 'httpbin.org') {
      console.log(`Flagging tab ${tabId} for User-Agent modification: ${tab.url}`);
      modifiedTabs.add(tabId);
      
      // Update badge to show modified tabs count
      chrome.action.setBadgeText({
        text: modifiedTabs.size.toString(),
        tabId: tabId
      });
      chrome.action.setBadgeBackgroundColor({color: '#FF0000'});
      
      // Store tab info
      chrome.storage.local.set({
        [`tab_${tabId}`]: {
          url: tab.url,
          modified: true,
          timestamp: Date.now()
        }
      });
      
      // Send message to content script
      chrome.tabs.sendMessage(tabId, {
        type: 'USER_AGENT_MODIFIED',
        userAgent: 'CustomBrowser/1.0 (Test Extension)'
      }).catch(() => {
        // Content script might not be ready yet, that's OK
      });
    }
  }
});

// Clean up when tab is closed
chrome.tabs.onRemoved.addListener((tabId) => {
  if (modifiedTabs.has(tabId)) {
    console.log(`Cleaning up closed tab ${tabId}`);
    modifiedTabs.delete(tabId);
    chrome.storage.local.remove(`tab_${tabId}`);
  }
});

// Handle messages from content scripts
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'GET_TAB_STATUS') {
    const isModified = modifiedTabs.has(sender.tab.id);
    sendResponse({
      modified: isModified,
      userAgent: isModified ? 'CustomBrowser/1.0 (Test Extension)' : navigator.userAgent
    });
  }
  
  if (message.type === 'REQUEST_INFO') {
    // Get current tab's request info
    chrome.storage.local.get(`tab_${sender.tab.id}`, (result) => {
      sendResponse(result[`tab_${sender.tab.id}`] || {modified: false});
    });
    return true; // Keep message channel open for async response
  }
});

// Set up declarativeNetRequest rules to modify headers
chrome.runtime.onInstalled.addListener(() => {
  console.log('Custom User Agent extension installed');
  
  // Note: In a real implementation, we'd need to dynamically update rules
  // based on which tabs are flagged, but declarativeNetRequest has limitations
  // For this test, we'll modify headers for all requests to target domains
  chrome.declarativeNetRequest.updateDynamicRules({
    addRules: [{
      id: 1,
      priority: 1,
      action: {
        type: 'modifyHeaders',
        requestHeaders: [{
          header: 'User-Agent',
          operation: 'set',
          value: 'CustomBrowser/1.0 (Test Extension)'
        }]
      },
      condition: {
        urlFilter: '*://example.com/*',
        resourceTypes: ['main_frame', 'sub_frame', 'xmlhttprequest', 'script', 'image']
      }
    }, {
      id: 2,
      priority: 1,
      action: {
        type: 'modifyHeaders',
        requestHeaders: [{
          header: 'User-Agent',
          operation: 'set',
          value: 'CustomBrowser/1.0 (Test Extension)'
        }]
      },
      condition: {
        urlFilter: '*://httpbin.org/*',
        resourceTypes: ['main_frame', 'sub_frame', 'xmlhttprequest', 'script', 'image']
      }
    }],
    removeRuleIds: []
  });
});