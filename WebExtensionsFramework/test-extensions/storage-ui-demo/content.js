// Content script for Storage UI Demo
console.log('Storage UI Demo: Content script started');

// State management
let currentStorageArea = 'local';
let quotaUsage = { local: 0, sync: 0, session: 0, managed: 0 };
let storageData = { local: {}, sync: {}, session: {}, managed: {} };
let trustedAccess = false;

// Initialize the demo
function init() {
  console.log('Storage UI Demo: Initializing...');
  
  // Request trusted access from background script
  chrome.runtime.sendMessage({ type: 'requestTrustedAccess' }, (response) => {
    if (response && response.success) {
      trustedAccess = true;
      console.log('Storage UI Demo: Trusted access granted');
    } else {
      console.warn('Storage UI Demo: Trusted access denied:', response?.error);
    }
    
    createUI();
    loadAllStorageData();
    setupStorageChangeListener();
  });
}

// Create the UI interface
function createUI() {
  // Check if UI already exists
  if (document.getElementById('storage-ui-demo')) {
    return;
  }
  
  const container = document.createElement('div');
  container.id = 'storage-ui-demo';
  container.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    width: 400px;
    max-height: 900px;
    overflow-y: auto;
    background: #ffffff;
    border: 2px solid #333;
    border-radius: 8px;
    box-shadow: 0 4px 20px rgba(0,0,0,0.3);
    z-index: 10000;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    font-size: 12px;
    line-height: 1.2;
  `;
  
  // Reset all default margins and padding for child elements
  container.style.cssText += `
    * { margin: 0; padding: 0; box-sizing: border-box; }
  `;
  
  container.innerHTML = `
    <div style="padding: 8px; border-bottom: 1px solid #eee; background: #f8f9fa;">
      <h3 style="margin: 0; font-size: 16px; color: #333;;">Chrome Storage UI Demo</h3>
      <button id="close-demo" style="position: absolute; top: 8px; right: 8px; background: #dc3545; color: white; border: none; border-radius: 3px; padding: 4px 8px; cursor: pointer;">×</button>
    </div>

    <div style="padding: 0 !important; margin: 0 !important; border:1px solid #000f;">
      <!-- Storage Area Selection -->
      <div style="margin: 0 !important; padding: 0 !important; ">
        <label style="display: block; margin: 0; padding: 0; font-weight: bold;">Storage Area:</label>
        <select id="storage-area-select" style="width: 100%; margin: 0; padding: 4px 6px; border: 1px solid #ddd; border-radius: 4px; line-height: 1.2;">
          <option value="local">Local Storage</option>
          <option value="sync">Sync Storage</option>
          <option value="session">Session Storage ${trustedAccess ? '(Trusted)' : '(Limited)'}</option>
          <option value="managed">Managed Storage (Read-only)</option>
        </select>
        <div style="margin: 0; padding: 0; font-size: 10px; color: #666; ">
          <span style="font-weight: bold;">Quota:</span> <span id="quota-bars" style=""></span>
        </div>
      </div>
      
      <!-- Add/Update Operation -->
      <div style="margin: 0 0 8px 0 !important; padding: 4px !important; border: 1px solid #ddd; border-radius: 4px;">
        <h4 style="margin: 0 0 12px 0;">Add/Update Data</h4>
        <input type="text" id="key-input" placeholder="Key" style="width: calc(50% - 4px); padding: 6px; border: 1px solid #ddd; border-radius: 3px; margin-right: 8px;">
        <input type="text" id="value-input" placeholder="Value (JSON)" style="width: calc(50% - 4px); padding: 6px; border: 1px solid #ddd; border-radius: 3px;">
        <button id="set-btn" style="width: 100%; margin-top: 8px; padding: 8px; background: #007bff; color: white; border: none; border-radius: 4px; cursor: pointer;">Set Data</button>
      </div>
      
      <!-- Query Operation -->
      <div style="margin: 0 0 8px 0 !important; padding: 4px !important; border: 1px solid #ddd; border-radius: 4px;">
        <h4 style="margin: 0 0 6px 0;">Query Data</h4>
        <input type="text" id="query-input" placeholder="Key(s) - leave empty for all" style="width: calc(70% - 4px); padding: 6px; border: 1px solid #ddd; border-radius: 3px; margin-right: 8px;">
        <button id="get-btn" style="width: calc(30% - 4px); padding: 6px; background: #28a745; color: white; border: none; border-radius: 3px; cursor: pointer;">Get</button>
      </div>
      
      <!-- Remove Operation -->
      <div style="margin: 0 0 8px 0 !important; padding: 4px !important; border: 1px solid #ddd; border-radius: 4px;">
        <h4 style="margin: 0 0 6px 0;">Remove Data</h4>
        <input type="text" id="remove-input" placeholder="Key(s) to remove" style="width: calc(60% - 4px); padding: 6px; border: 1px solid #ddd; border-radius: 3px; margin-right: 8px;">
        <button id="remove-btn" style="width: calc(20% - 4px); padding: 6px; background: #dc3545; color: white; border: none; border-radius: 3px; cursor: pointer; margin-right: 8px;">Remove</button>
        <button id="clear-btn" style="width: calc(20% - 4px); padding: 6px; background: #6c757d; color: white; border: none; border-radius: 3px; cursor: pointer;">Clear All</button>
      </div>
      
      <!-- Data Display -->
      <div style="margin: 0 0 8px 0 !important; padding: 0 !important;">
        <h4 style="margin: 0 0 12px 0; color: #333 !important;">Current Data</h4>
        <pre id="data-display" style="background: #f8f9fa; padding: 12px; border-radius: 4px; max-height: 200px; overflow-y: auto; font-size: 11px; margin: 0; white-space: pre-wrap; color: #333 !important;"></pre>
      </div>
      
      <!-- Log Display -->
      <div style="margin: 0 !important; padding: 0 !important;">
        <h4 style="margin: 0 0 12px 0;">Activity Log</h4>
        <div id="log-display" style="background: #1a1a1a; color: #0f0; padding: 8px; border-radius: 4px; max-height: 150px; overflow-y: auto; font-family: 'Menlo', 'Monaco', monospace; font-size: 11px; line-height: 1.4;"></div>
        <button id="clear-log-btn" style="width: 100%; margin-top: 8px; padding: 6px; background: #6c757d; color: white; border: none; border-radius: 3px; cursor: pointer;">Clear Log</button>
      </div>
    </div>
  `;
  
  document.body.appendChild(container);
  
  // Add event listeners
  setupEventListeners();
  
  log('UI Demo initialized successfully');
}

// Set up event listeners
function setupEventListeners() {
  // Close button
  document.getElementById('close-demo').addEventListener('click', () => {
    document.getElementById('storage-ui-demo').remove();
  });
  
  // Storage area selection
  document.getElementById('storage-area-select').addEventListener('change', (e) => {
    currentStorageArea = e.target.value;
    updateDataDisplay();
    updateQuotaDisplay();
    log(`Switched to ${currentStorageArea} storage area`);
  });
  
  // Set data button
  document.getElementById('set-btn').addEventListener('click', setData);
  
  // Get data button  
  document.getElementById('get-btn').addEventListener('click', getData);
  
  // Remove data button
  document.getElementById('remove-btn').addEventListener('click', removeData);
  
  // Clear all button
  document.getElementById('clear-btn').addEventListener('click', clearAllData);
  
  // Clear log button
  document.getElementById('clear-log-btn').addEventListener('click', () => {
    document.getElementById('log-display').innerHTML = '';
  });
  
  // Enter key handlers
  document.getElementById('key-input').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') setData();
  });
  document.getElementById('value-input').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') setData();
  });
  document.getElementById('query-input').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') getData();
  });
  document.getElementById('remove-input').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') removeData();
  });
}

// Storage operations
async function setData() {
  const key = document.getElementById('key-input').value.trim();
  const valueStr = document.getElementById('value-input').value.trim();
  
  if (!key || !valueStr) {
    log('Error: Both key and value are required', 'error');
    return;
  }
  
  let value;
  try {
    value = JSON.parse(valueStr);
  } catch (e) {
    // If JSON parsing fails, treat as string
    value = valueStr;
  }
  
  const data = { [key]: value };
  
  try {
    await performStorageOperation('set', data);
    document.getElementById('key-input').value = '';
    document.getElementById('value-input').value = '';
    log(`Set ${key} = ${JSON.stringify(value)} in ${currentStorageArea}`);
  } catch (error) {
    log(`Error setting data: ${error.message}`, 'error');
  }
}

async function getData() {
  log('getData called');
  const queryStr = document.getElementById('query-input').value.trim();
  let keys = null;
  
  if (queryStr) {
    // Parse comma-separated keys or single key
    keys = queryStr.includes(',') ? 
      queryStr.split(',').map(k => k.trim()) : 
      [queryStr];
  }
  
  log(`Query string: '${queryStr}', keys: ${keys === null ? 'null' : JSON.stringify(keys)}`);
  
  try {
    const result = await performStorageOperation('get', keys);
    // Update the display to show the retrieved data
    if (!keys) {
      // If getting all keys, update the stored data and show all
      storageData[currentStorageArea] = result;
      updateDataDisplay();
    } else {
      // If getting specific keys, merge the results into stored data but show only the query results
      storageData[currentStorageArea] = { ...storageData[currentStorageArea], ...result };
      updateDataDisplay(result); // Show only the queried data
    }
    log(`Retrieved ${keys ? JSON.stringify(keys) : 'all keys'} from ${currentStorageArea}: ${Object.keys(result).length} item(s)`);
  } catch (error) {
    log(`Error getting data: ${error.message || error.toString()}`, 'error');
  }
}

async function removeData() {
  const keysStr = document.getElementById('remove-input').value.trim();
  
  if (!keysStr) {
    log('Error: Key(s) required for removal', 'error');
    return;
  }
  
  const keys = keysStr.includes(',') ? 
    keysStr.split(',').map(k => k.trim()) : 
    [keysStr];
  
  try {
    await performStorageOperation('remove', keys);
    document.getElementById('remove-input').value = '';
    log(`Removed ${JSON.stringify(keys)} from ${currentStorageArea}`);
  } catch (error) {
    log(`Error removing data: ${error.message}`, 'error');
  }
}

async function clearAllData() {
  if (!confirm(`Clear all data from ${currentStorageArea} storage?`)) {
    return;
  }
  
  try {
    await performStorageOperation('clear');
    log(`Cleared all data from ${currentStorageArea}`);
  } catch (error) {
    log(`Error clearing data: ${error.message}`, 'error');
  }
}

// Perform storage operations (handles session storage through background script)
function performStorageOperation(operation, data) {
  log(`performStorageOperation called: ${operation}, data: ${data === null ? 'null' : JSON.stringify(data)}`);
  return new Promise((resolve, reject) => {
    if (currentStorageArea === 'session' && trustedAccess) {
      // Use background script for session storage operations
      const message = {
        type: 'performTrustedOperation',
        operation: `session${operation.charAt(0).toUpperCase() + operation.slice(1)}`,
        data: operation === 'set' ? data : undefined,
        keys: operation === 'get' || operation === 'remove' ? data : undefined
      };
      
      chrome.runtime.sendMessage(message, (response) => {
        if (response && response.success) {
          if (operation === 'get') {
            storageData.session = response.data || {};
          }
          loadAllStorageData();
          resolve(response.data);
        } else {
          reject(new Error(response?.error || 'Unknown error'));
        }
      });
    } else if (currentStorageArea === 'managed') {
      // Managed storage is read-only
      if (operation !== 'get') {
        reject(new Error('Managed storage is read-only'));
        return;
      }
      
      chrome.storage.managed.get(data, (result) => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
        } else {
          storageData.managed = result;
          updateDataDisplay();
          resolve(result);
        }
      });
    } else {
      // Use direct API for local, sync, and non-trusted session
      const storageAPI = chrome.storage[currentStorageArea];
      
      switch (operation) {
        case 'set':
          storageAPI.set(data, () => {
            if (chrome.runtime.lastError) {
              reject(new Error(chrome.runtime.lastError.message));
            } else {
              loadAllStorageData();
              resolve();
            }
          });
          break;
          
        case 'get':
          log(`Calling ${currentStorageArea}.get with: ${data === null ? 'null' : JSON.stringify(data)}`);
          try {
            storageAPI.get(data, (result) => {
              if (chrome.runtime.lastError) {
                log(`${currentStorageArea}.get error: ${chrome.runtime.lastError.message}`, 'error');
                reject(new Error(chrome.runtime.lastError.message));
              } else {
                log(`${currentStorageArea}.get success, got ${Object.keys(result || {}).length} keys`);
                resolve(result);
              }
            });
          } catch (e) {
            log(`${currentStorageArea}.get exception: ${e.toString()}`, 'error');
            reject(e);
          }
          break;
          
        case 'remove':
          storageAPI.remove(data, () => {
            if (chrome.runtime.lastError) {
              reject(new Error(chrome.runtime.lastError.message));
            } else {
              loadAllStorageData();
              resolve();
            }
          });
          break;
          
        case 'clear':
          storageAPI.clear(() => {
            if (chrome.runtime.lastError) {
              reject(new Error(chrome.runtime.lastError.message));
            } else {
              loadAllStorageData();
              resolve();
            }
          });
          break;
          
        default:
          reject(new Error(`Unknown operation: ${operation}`));
      }
    }
  });
}

// Load data from all storage areas
function loadAllStorageData() {
  // Load local storage
  chrome.storage.local.get(null, (result) => {
    storageData.local = result || {};
    updateDataDisplay();
    updateQuotaUsage('local');
  });
  
  // Load sync storage
  chrome.storage.sync.get(null, (result) => {
    storageData.sync = result || {};
    updateDataDisplay();
    updateQuotaUsage('sync');
  });
  
  // Load session storage (through background if trusted)
  if (trustedAccess) {
    chrome.runtime.sendMessage({
      type: 'performTrustedOperation',
      operation: 'sessionGet',
      keys: null
    }, (response) => {
      if (response && response.success) {
        storageData.session = response.data || {};
        updateDataDisplay();
        updateQuotaUsage('session');
      }
    });
  } else {
    chrome.storage.session.get(null, (result) => {
      storageData.session = result || {};
      updateDataDisplay();
      updateQuotaUsage('session');
    });
  }
  
  // Load managed storage
  chrome.storage.managed.get(null, (result) => {
    storageData.managed = result || {};
    updateDataDisplay();
    updateQuotaUsage('managed');
  });
}

// Update quota usage calculation
function updateQuotaUsage(area) {
  const data = storageData[area];
  const jsonString = JSON.stringify(data);
  const bytes = new Blob([jsonString]).size;
  
  quotaUsage[area] = bytes;
  updateQuotaDisplay();
}

// Update quota display
function updateQuotaDisplay() {
  const quotaBars = document.getElementById('quota-bars');
  if (!quotaBars) return;
  
  // Storage limits (approximate)
  const limits = {
    local: 10485760, // 10MB
    sync: 102400,    // 100KB  
    session: 1048576, // 1MB
    managed: 0       // No limit (read-only)
  };
  
  let items = [];
  Object.keys(limits).forEach(area => {
    const usage = quotaUsage[area] || 0;
    const limit = limits[area];
    const percentage = limit > 0 ? Math.min((usage / limit) * 100, 100) : 0;
    const color = percentage > 80 ? '#dc3545' : percentage > 50 ? '#ffc107' : '#28a745';
    
    items.push(`${area}: ${usage}b <span style="display:inline-block;width:20px;height:2px;background:${color};vertical-align:middle;"></span>`);
  });
  
  quotaBars.innerHTML = items.join(' | ');
}

// Update data display
function updateDataDisplay(specificData = null) {
  const display = document.getElementById('data-display');
  if (!display) {
    log('ERROR: data-display element not found!', 'error');
    return;
  }
  
  const data = specificData || storageData[currentStorageArea] || {};
  log(`Updating display for ${currentStorageArea}: ${JSON.stringify(data)}`);
  display.textContent = JSON.stringify(data, null, 2);
}

// Set up storage change listener
function setupStorageChangeListener() {
  chrome.storage.onChanged.addListener((changes, areaName) => {
    log(`Storage changed in ${areaName}: ${JSON.stringify(changes)}`);
    
    // Reload data for the changed area
    if (areaName === 'local') {
      chrome.storage.local.get(null, (result) => {
        storageData.local = result || {};
        updateDataDisplay();
        updateQuotaUsage('local');
      });
    } else if (areaName === 'sync') {
      chrome.storage.sync.get(null, (result) => {
        storageData.sync = result || {};
        updateDataDisplay();
        updateQuotaUsage('sync');
      });
    } else if (areaName === 'session') {
      if (trustedAccess) {
        chrome.runtime.sendMessage({
          type: 'performTrustedOperation',
          operation: 'sessionGet',
          keys: null
        }, (response) => {
          if (response && response.success) {
            storageData.session = response.data || {};
            updateDataDisplay();
            updateQuotaUsage('session');
          }
        });
      } else {
        chrome.storage.session.get(null, (result) => {
          storageData.session = result || {};
          updateDataDisplay();
          updateQuotaUsage('session');
        });
      }
    }
  });
}

// Logging function
function log(message, type = 'info') {
  console.log(`Storage UI Demo: ${message}`);
  
  const logDisplay = document.getElementById('log-display');
  if (logDisplay) {
    const timestamp = new Date().toLocaleTimeString();
    const color = type === 'error' ? '#f00' : type === 'warn' ? '#fa0' : '#0f0';
    const logEntry = `<div style="color: ${color};">[${timestamp}] ${message}</div>`;
    logDisplay.innerHTML += logEntry;
    logDisplay.scrollTop = logDisplay.scrollHeight;
  }
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
