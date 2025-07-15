// Content script for storage demo
console.log('Storage Demo: Content script started');

// Function to read data from storage and display it
function displayStorageData() {
  // Get data from local storage
  chrome.storage.local.get(null, (localData) => {
    console.log('Storage Demo: Local storage data:', localData);
    
    // Get data from sync storage
    chrome.storage.sync.get(null, (syncData) => {
      console.log('Storage Demo: Sync storage data:', syncData);
      
      // Get data from session storage
      chrome.storage.session.get(null, (sessionData) => {
        console.log('Storage Demo: Session storage data:', sessionData);
        
        // Create a visual display of the data
        try {
            displayDataOnPage({
              local: localData,
              sync: syncData,
              session: sessionData
            });
        } catch(e) {
            console.log('Storage Demo: Error displaying data:", e.toString());
        }
      });
    });
  });
}

// Function to display data on the page
function displayDataOnPage(storageData) {
  // Remove any existing display
  const existingDisplay = document.getElementById('storage-demo-display');
  if (existingDisplay) {
    existingDisplay.remove();
  }
  
  // Create display element
  const display = document.createElement('div');
  display.id = 'storage-demo-display';
  display.style.cssText = `
    position: fixed;
    top: 10px;
    right: 10px;
    width: 300px;
    background: #f0f0f0;
    border: 2px solid #333;
    border-radius: 8px;
    padding: 15px;
    font-family: monospace;
    font-size: 12px;
    z-index: 10000;
    max-height: 400px;
    overflow-y: auto;
    box-shadow: 0 4px 8px rgba(0,0,0,0.2);
  `;
  
  // Create content
  const title = document.createElement('h3');
  title.textContent = 'Storage Demo Data';
  title.style.cssText = 'margin: 0 0 10px 0; color: #333;';
  display.appendChild(title);
  
  // Add storage data sections
  for (const [storageType, data] of Object.entries(storageData)) {
    const section = document.createElement('div');
    section.style.cssText = 'margin-bottom: 10px; padding: 5px; background: white; border-radius: 4px;';
    
    const header = document.createElement('strong');
    header.textContent = `${storageType.toUpperCase()} Storage:`;
    header.style.cssText = 'display: block; margin-bottom: 5px; color: #666;';
    section.appendChild(header);
    
    const content = document.createElement('pre');
    content.textContent = JSON.stringify(data, null, 2);
    content.style.cssText = 'margin: 0; font-size: 10px; white-space: pre-wrap; word-wrap: break-word;';
    section.appendChild(content);
    
    display.appendChild(section);
  }
  
  // Add buttons
  const buttonContainer = document.createElement('div');
  buttonContainer.style.cssText = 'margin-top: 10px; display: flex; gap: 5px;';
  
  const incrementButton = document.createElement('button');
  incrementButton.textContent = 'Increment Counter';
  incrementButton.style.cssText = 'padding: 5px 10px; background: #4CAF50; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 10px;';
  incrementButton.onclick = incrementCounter;
  
  const refreshButton = document.createElement('button');
  refreshButton.textContent = 'Refresh Data';
  refreshButton.style.cssText = 'padding: 5px 10px; background: #2196F3; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 10px;';
  refreshButton.onclick = displayStorageData;
  
  const clearButton = document.createElement('button');
  clearButton.textContent = 'Clear Local';
  clearButton.style.cssText = 'padding: 5px 10px; background: #f44336; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 10px;';
  clearButton.onclick = clearLocalStorage;
  
  buttonContainer.appendChild(incrementButton);
  buttonContainer.appendChild(refreshButton);
  buttonContainer.appendChild(clearButton);
  display.appendChild(buttonContainer);
  
  // Add to page
  document.body.appendChild(display);
}

// Function to increment counter via background script
function incrementCounter() {
  console.log('Storage Demo: Requesting counter increment');
  chrome.runtime.sendMessage({
    type: 'increment_counter'
  }, (response) => {
    console.log('Storage Demo: Counter increment response:', response);
    if (response && response.success) {
      // Refresh the display
      displayStorageData();
    }
  });
}

// Function to clear local storage
function clearLocalStorage() {
  console.log('Storage Demo: Clearing local storage');
  chrome.storage.local.clear(() => {
    console.log('Storage Demo: Local storage cleared');
    displayStorageData();
  });
}

// Wait for page to load, then display data
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', displayStorageData);
} else {
  displayStorageData();
}

// Listen for storage changes
chrome.storage.onChanged.addListener((changes, areaName) => {
  console.log('Storage Demo: Storage changed in', areaName, ':', changes);
  // Refresh display when storage changes
  displayStorageData();
});

console.log('Storage Demo: Content script initialization complete');
