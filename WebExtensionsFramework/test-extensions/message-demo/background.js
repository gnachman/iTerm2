// Background service worker for Message Demo extension
console.log('Message Demo background script started');

// Keep track of message statistics
let messageStats = {
  totalMessages: 0,
  pageLoads: 0,
  userClicks: 0,
  periodicUpdates: 0
};

// Listen for messages from content scripts
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('Background received message:', message);
  console.log('Message sender:', sender);
  
  // Update statistics
  messageStats.totalMessages++;
  
  // Handle different message types
  let responseMessage = '';
  
  switch (message.type) {
    case 'page_loaded':
      messageStats.pageLoads++;
      responseMessage = `Page loaded: ${message.url}`;
      console.log(`Page loaded event from tab ${sender.tab?.id}: ${message.url}`);
      break;
      
    case 'user_click':
      messageStats.userClicks++;
      responseMessage = `User clicked (${message.clickCount} times)`;
      console.log(`User click event from tab ${sender.tab?.id}, click count: ${message.clickCount}`);
      break;
      
    case 'periodic_update':
      messageStats.periodicUpdates++;
      responseMessage = `Periodic update from ${message.url}`;
      console.log(`Periodic update from tab ${sender.tab?.id}: ${message.url}`);
      break;
      
    default:
      responseMessage = `Unknown message type: ${message.type}`;
      console.log('Unknown message type received:', message.type);
  }
  
  // Log current statistics
  console.log('Current message statistics:', messageStats);
  
  // Send response back to content script
  const response = {
    success: true,
    message: responseMessage,
    count: messageStats.totalMessages,
    stats: messageStats,
    timestamp: Date.now(),
    receivedAt: new Date().toISOString()
  };
  
  console.log('Background sending response:', response);
  sendResponse(response);
  
  // Return true to indicate we will send a response asynchronously
  return true;
});

// Log statistics every 30 seconds
setInterval(() => {
  console.log('=== Message Demo Extension Statistics ===');
  console.log('Total messages received:', messageStats.totalMessages);
  console.log('Page loads:', messageStats.pageLoads);
  console.log('User clicks:', messageStats.userClicks);
  console.log('Periodic updates:', messageStats.periodicUpdates);
  console.log('==========================================');
}, 30000);

console.log('Message Demo background script ready to receive messages');