// Content script for Custom User Agent extension

console.log('Custom User Agent content script loaded');

// Create a banner to show current User-Agent info
function createUserAgentBanner() {
  // Remove existing banner if present
  const existing = document.getElementById('custom-ua-banner');
  if (existing) existing.remove();
  
  const banner = document.createElement('div');
  banner.id = 'custom-ua-banner';
  banner.style.cssText = `
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    background: #ff4444;
    color: white;
    padding: 10px;
    font-family: monospace;
    font-size: 12px;
    z-index: 10000;
    border-bottom: 2px solid #cc0000;
    box-shadow: 0 2px 5px rgba(0,0,0,0.3);
  `;
  banner.innerHTML = `
    <strong>🔧 Custom User Agent Extension Active</strong><br>
    <span id="ua-display">Loading...</span><br>
    <small>Original User-Agent: ${navigator.userAgent}</small>
  `;
  
  document.body.insertBefore(banner, document.body.firstChild);
  
  // Adjust body margin to prevent banner from covering content
  document.body.style.marginTop = '80px';
  
  return banner;
}

// Update the banner with current User-Agent info
function updateBanner() {
  const display = document.getElementById('ua-display');
  if (!display) return;
  
  // Get tab status from background script
  chrome.runtime.sendMessage({type: 'GET_TAB_STATUS'}, (response) => {
    if (response) {
      display.innerHTML = response.modified 
        ? `<span style="color: #90EE90;">✅ Modified User-Agent: ${response.userAgent}</span>`
        : `<span style="color: #FFB6C1;">❌ Using original User-Agent</span>`;
    }
  });
  
  // Also test by making a request to see what User-Agent is actually sent
  fetch('/headers.json', {method: 'GET'})
    .then(response => response.json())
    .then(data => {
      const sentUA = data.headers?.['User-Agent'] || 'Unknown';
      const statusElement = document.createElement('div');
      statusElement.innerHTML = `<small style="color: #FFFF99;">Actual sent User-Agent: ${sentUA}</small>`;
      display.appendChild(statusElement);
    })
    .catch(() => {
      // If headers.json doesn't exist, try httpbin.org
      if (window.location.hostname === 'httpbin.org' || window.location.hostname === 'example.com') {
        fetch('https://httpbin.org/headers')
          .then(response => response.json())
          .then(data => {
            const sentUA = data.headers?.['User-Agent'] || 'Unknown';
            const statusElement = document.createElement('div');
            statusElement.innerHTML = `<small style="color: #FFFF99;">Actual sent User-Agent: ${sentUA}</small>`;
            display.appendChild(statusElement);
          })
          .catch(console.error);
      }
    });
}

// Listen for messages from background script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'USER_AGENT_MODIFIED') {
    console.log('User-Agent modification confirmed:', message.userAgent);
    updateBanner();
  }
});

// Initialize when page loads
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    createUserAgentBanner();
    setTimeout(updateBanner, 1000); // Give time for background script to process
  });
} else {
  createUserAgentBanner();
  setTimeout(updateBanner, 1000);
}

// Add a test button to manually check User-Agent
setTimeout(() => {
  if (document.getElementById('custom-ua-banner')) {
    const testButton = document.createElement('button');
    testButton.textContent = 'Test User-Agent';
    testButton.style.cssText = 'margin-left: 10px; padding: 2px 8px; font-size: 10px;';
    testButton.onclick = () => {
      // Make a test request to check what User-Agent is actually being sent
      fetch('https://httpbin.org/user-agent', {
        method: 'GET',
        cache: 'no-cache'
      })
      .then(response => response.json())
      .then(data => {
        alert(`Sent User-Agent: ${data['user-agent']}`);
      })
      .catch(err => {
        console.error('Test request failed:', err);
        alert('Test request failed - check console');
      });
    };
    document.getElementById('custom-ua-banner').appendChild(testButton);
  }
}, 2000);