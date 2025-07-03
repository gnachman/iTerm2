// Popup script for Custom User Agent extension

document.addEventListener('DOMContentLoaded', async () => {
  const statusElement = document.getElementById('tab-status');
  const testButton = document.getElementById('test-button');
  const refreshButton = document.getElementById('refresh-button');
  
  // Get current tab info
  async function updateStatus() {
    try {
      const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
      
      if (tab) {
        // Check if this tab is being modified
        const url = new URL(tab.url);
        const isTargetDomain = url.hostname === 'example.com' || url.hostname === 'httpbin.org';
        
        if (isTargetDomain) {
          statusElement.innerHTML = `
            <div class="modified">
              ✅ <strong>User-Agent Modified</strong><br>
              <small>Domain: ${url.hostname}</small><br>
              <small>Tab ID: ${tab.id}</small>
            </div>
          `;
          document.getElementById('status').className = 'status modified';
        } else {
          statusElement.innerHTML = `
            <div class="normal">
              ❌ <strong>Normal User-Agent</strong><br>
              <small>Domain: ${url.hostname}</small><br>
              <small>Not a target domain</small>
            </div>
          `;
          document.getElementById('status').className = 'status normal';
        }
        
        // Get stored tab data
        chrome.storage.local.get(`tab_${tab.id}`, (result) => {
          const tabData = result[`tab_${tab.id}`];
          if (tabData) {
            const timestamp = new Date(tabData.timestamp).toLocaleTimeString();
            statusElement.innerHTML += `<br><small>Modified at: ${timestamp}</small>`;
          }
        });
      }
    } catch (error) {
      statusElement.innerHTML = `<div class="normal">❌ Error: ${error.message}</div>`;
    }
  }
  
  // Test button functionality
  testButton.addEventListener('click', async () => {
    testButton.textContent = 'Testing...';
    testButton.disabled = true;
    
    try {
      // Get current tab
      const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
      
      if (tab) {
        // Send message to content script to run test
        const response = await chrome.tabs.sendMessage(tab.id, {
          type: 'RUN_TEST'
        });
        
        if (response) {
          alert(`Test completed!\nSent User-Agent: ${response.userAgent}`);
        } else {
          // Fallback: open httpbin.org in new tab for testing
          chrome.tabs.create({url: 'https://httpbin.org/user-agent'});
        }
      }
    } catch (error) {
      console.error('Test failed:', error);
      // Fallback: open test page
      chrome.tabs.create({url: 'https://httpbin.org/user-agent'});
    }
    
    testButton.textContent = 'Test User-Agent Request';
    testButton.disabled = false;
  });
  
  // Refresh button
  refreshButton.addEventListener('click', updateStatus);
  
  // Initial status update
  updateStatus();
  
  // Listen for storage changes
  chrome.storage.onChanged.addListener((changes, namespace) => {
    if (namespace === 'local') {
      updateStatus();
    }
  });
});