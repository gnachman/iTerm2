// Content script for Message Demo extension
console.log('Message Demo content script loaded!');

// Create a visual indicator that the extension is active
const indicator = document.createElement('div');
indicator.textContent = 'Message Demo Extension Active - Click to send message!';

try {
    indicator.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      height: 60px;
      background: #4CAF50;
      color: white;
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: Arial, sans-serif;
      font-weight: bold;
      z-index: 9999;
      cursor: pointer;
      border-bottom: 3px solid #45a049;
    `;

    document.body.appendChild(indicator);

    // Function to send a message to the background script
    function sendMessageToBackground(messageData) {
      console.log('Content script sending message:', messageData);
      
      chrome.runtime.sendMessage(messageData, (response) => {
        console.log('Content script received response:', response);
        
        // Update the indicator to show the response
        if (response && response.success) {
          indicator.style.background = '#2196F3';
          indicator.textContent = `Response: ${response.message} (Count: ${response.count})`;
        } else {
          indicator.style.background = '#f44336';
          indicator.textContent = 'Error: No response received';
        }
        
        // Reset after 3 seconds
        setTimeout(() => {
          indicator.style.background = '#4CAF50';
          indicator.textContent = 'Message Demo Extension Active - Click to send message!';
        }, 3000);
      });
    }

    // Send initial message when content script loads
    sendMessageToBackground({
      type: 'page_loaded',
      url: window.location.href,
      timestamp: Date.now()
    });

    // Add click handler to send messages on demand
    let messageCount = 0;
    indicator.addEventListener('click', () => {
          indicator.textContent = 'Click';
      messageCount++;
      sendMessageToBackground({
        type: 'user_click',
        url: window.location.href,
        clickCount: messageCount,
        timestamp: Date.now()
      });
    });

    // Send a message every 10 seconds to demonstrate ongoing communication
    setInterval(() => {
      sendMessageToBackground({
        type: 'periodic_update',
        url: window.location.href,
        timestamp: Date.now()
      });
    }, 10000);
} catch (error) {
        indicator.textContent = `Error: ${error.message || error}`;
}
