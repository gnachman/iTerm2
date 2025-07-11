// Background service worker for storage demo
console.log('Storage Demo: Background script started');

// Store initial data when extension starts
chrome.storage.local.set({
  'background_data': {
    message: 'Hello from background!',
    timestamp: Date.now(),
    counter: 0
  },
  'user_preferences': {
    theme: 'dark',
    notifications: true
  }
}, () => {
  console.log('Storage Demo: Initial data stored in background');
});

// Listen for messages from content script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('Storage Demo: Background received message:', message);
  
  if (message.type === 'increment_counter') {
    // Get current counter value and increment it
    chrome.storage.local.get(['background_data'], (result) => {
      const data = result.background_data || { counter: 0 };
      data.counter = (data.counter || 0) + 1;
      data.timestamp = Date.now();
      
      // Store updated data
      chrome.storage.local.set({ 'background_data': data }, () => {
        console.log('Storage Demo: Counter incremented to', data.counter);
        sendResponse({ 
          success: true, 
          counter: data.counter,
          message: 'Counter updated successfully'
        });
      });
    });
    
    return true; // Keep message channel open for async response
  }
  
  if (message.type === 'get_stats') {
    // Get all stored data for stats
    chrome.storage.local.get(null, (result) => {
      console.log('Storage Demo: All stored data:', result);
      sendResponse({
        success: true,
        data: result
      });
    });
    
    return true; // Keep message channel open for async response
  }
});

// Demonstrate sync storage (though it will work like local in our implementation)
chrome.storage.sync.set({
  'sync_data': {
    userId: 'demo-user-123',
    lastSync: Date.now()
  }
}, () => {
  console.log('Storage Demo: Sync data stored');
});

// Test session storage
chrome.storage.session.set({
  'session_data': {
    sessionId: Math.random().toString(36).substr(2, 9),
    startTime: Date.now()
  }
}, () => {
  console.log('Storage Demo: Session data stored');
});

console.log('Storage Demo: Background script initialization complete');