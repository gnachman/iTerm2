// Background script for Storage UI Demo
console.log('Storage UI Demo: Background script started');

// Grant trusted access to the content script for session storage
// This enables the content script to access session storage which is normally restricted
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'requestTrustedAccess') {
    console.log('Storage UI Demo: Granting trusted access for session storage');
    
    // Perform a privileged operation to demonstrate trusted access
    // In a real implementation, this would involve setting up trusted context
    chrome.storage.session.set({ 
      _trustedAccess: true,
      _accessGrantedAt: Date.now(),
      _grantedBy: 'background-script'
    }, () => {
      if (chrome.runtime.lastError) {
        console.error('Storage UI Demo: Error granting trusted access:', chrome.runtime.lastError);
        sendResponse({ success: false, error: chrome.runtime.lastError.message });
      } else {
        console.log('Storage UI Demo: Trusted access granted successfully');
        sendResponse({ success: true });
      }
    });
    
    return true; // Keep message channel open for async response
  }
  
  if (message.type === 'performTrustedOperation') {
    console.log('Storage UI Demo: Performing trusted operation:', message.operation);
    
    switch (message.operation) {
      case 'sessionGet':
        console.log('Storage UI Demo: sessionGet with keys:', message.keys);
        try {
          chrome.storage.session.get(message.keys, (result) => {
            if (chrome.runtime.lastError) {
              console.error('Storage UI Demo: sessionGet error:', chrome.runtime.lastError);
              sendResponse({ success: false, error: chrome.runtime.lastError.message });
            } else {
              sendResponse({ success: true, data: result });
            }
          });
        } catch (e) {
          console.log('Storage UI Demo: sessionGet exception:', e.toString());
          sendResponse({ success: false, error: e.toString() });
        }
        break;
        
      case 'sessionSet':
        chrome.storage.session.set(message.data, () => {
          if (chrome.runtime.lastError) {
            sendResponse({ success: false, error: chrome.runtime.lastError.message });
          } else {
            sendResponse({ success: true });
          }
        });
        break;
        
      case 'sessionRemove':
        chrome.storage.session.remove(message.keys, () => {
          if (chrome.runtime.lastError) {
            sendResponse({ success: false, error: chrome.runtime.lastError.message });
          } else {
            sendResponse({ success: true });
          }
        });
        break;
        
      case 'sessionClear':
        chrome.storage.session.clear(() => {
          if (chrome.runtime.lastError) {
            sendResponse({ success: false, error: chrome.runtime.lastError.message });
          } else {
            sendResponse({ success: true });
          }
        });
        break;
        
      default:
        sendResponse({ success: false, error: 'Unknown operation' });
    }
    
    return true; // Keep message channel open for async response
  }
});

// Set up some initial background data
chrome.storage.local.set({
  backgroundInitialized: true,
  backgroundStartTime: Date.now(),
  backgroundVersion: '1.0'
}, () => {
  console.log('Storage UI Demo: Background initialization data stored');
});

// Listen for storage changes and log them
chrome.storage.onChanged.addListener((changes, areaName) => {
  console.log('Storage UI Demo: Storage changed in', areaName, 'area:', changes);
});