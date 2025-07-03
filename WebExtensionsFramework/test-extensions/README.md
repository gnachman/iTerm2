# Test Extensions

This directory contains test extensions for validating the WebExtensions framework implementation.

## Custom User Agent Extension

**Purpose**: Tests browser-proxy context correlation by modifying User-Agent headers for specific domains.

**Location**: `custom-user-agent/`

### How to Test in Chrome

1. Open Chrome and go to `chrome://extensions/`
2. Enable "Developer mode" (toggle in top right)
3. Click "Load unpacked"
4. Select the `custom-user-agent` folder
5. The extension should appear with a toolbar icon

### Testing Steps

1. **Install Extension**: Load the extension in Chrome
2. **Visit Test Sites**: Navigate to:
   - `https://example.com` 
   - `https://httpbin.org/user-agent`
3. **Check Banner**: A red banner should appear showing the modified User-Agent
4. **Verify Headers**: On httpbin.org, you should see `CustomBrowser/1.0 (Test Extension)` as the User-Agent
5. **Test Button**: Click the "Test User-Agent" button in the banner for additional verification
6. **Popup Interface**: Click the extension icon to see status in the popup

### Expected Behavior

- ✅ Red banner appears on example.com and httpbin.org
- ✅ User-Agent shows as "CustomBrowser/1.0 (Test Extension)" 
- ✅ Extension badge shows count of modified tabs
- ✅ Popup shows current tab status
- ✅ httpbin.org/user-agent displays the custom User-Agent

### Key Features Tested

1. **declarativeNetRequest**: Header modification via rules
2. **chrome.tabs**: Tab monitoring and event handling  
3. **Content Scripts**: DOM manipulation and messaging
4. **Background Service Worker**: Persistent state management
5. **Storage API**: Tab state persistence
6. **Message Passing**: Content ↔ Background communication

This extension serves as the target implementation for our WebExtensions framework MVP. If we can replicate this exact functionality with our native implementation, we'll have validated the core architecture.