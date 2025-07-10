# permissions

The `permissions` field in the manifest.json file is used to request access to specific browser APIs that the extension needs to function.

## Manifest Field

```json
{
  "permissions": ["permission1", "permission2", ...]
}
```

- **Type**: Array of strings
- **Required**: No
- **Manifest Version**: 3

## Description

The permissions array contains strings that specify which browser APIs the extension wants to access. In Manifest V3, host permissions (URLs) must be specified in the separate `host_permissions` field, not in the `permissions` field.

## API Permissions

These are keywords that grant access to specific WebExtension APIs:

- `activeTab` - Provides temporary access to the currently active tab when the user invokes the extension
- `alarms` - Access to the chrome.alarms API
- `bookmarks` - Access to the chrome.bookmarks API
- `browsingData` - Access to the chrome.browsingData API
- `clipboardRead` - Read access to the clipboard
- `clipboardWrite` - Write access to the clipboard
- `contextMenus` - Access to the chrome.contextMenus API
- `cookies` - Access to the chrome.cookies API
- `debugger` - Access to the chrome.debugger API
- `declarativeContent` - Access to the chrome.declarativeContent API
- `declarativeNetRequest` - Access to the chrome.declarativeNetRequest API
- `declarativeNetRequestFeedback` - Access to the chrome.declarativeNetRequestFeedback API
- `desktopCapture` - Access to the chrome.desktopCapture API
- `downloads` - Access to the chrome.downloads API
- `fontSettings` - Access to the chrome.fontSettings API
- `gcm` - Access to the chrome.gcm API
- `geolocation` - Access to the geolocation API
- `history` - Access to the chrome.history API
- `identity` - Access to the chrome.identity API
- `idle` - Access to the chrome.idle API
- `management` - Access to the chrome.management API
- `nativeMessaging` - Access to native messaging
- `notifications` - Access to the chrome.notifications API
- `pageCapture` - Access to the chrome.pageCapture API
- `power` - Access to the chrome.power API
- `printerProvider` - Access to the chrome.printerProvider API
- `privacy` - Access to the chrome.privacy API
- `proxy` - Access to the chrome.proxy API
- `scripting` - Access to the chrome.scripting API
- `search` - Access to the chrome.search API
- `sessions` - Access to the chrome.sessions API
- `storage` - Access to the chrome.storage API
- `system.cpu` - Access to the chrome.system.cpu API
- `system.display` - Access to the chrome.system.display API
- `system.memory` - Access to the chrome.system.memory API
- `system.storage` - Access to the chrome.system.storage API
- `tabCapture` - Access to the chrome.tabCapture API
- `tabGroups` - Access to the chrome.tabGroups API
- `tabs` - Access to the chrome.tabs API
- `topSites` - Access to the chrome.topSites API
- `tts` - Access to the chrome.tts API
- `ttsEngine` - Access to the chrome.ttsEngine API
- `unlimitedStorage` - Removes the quota limit for chrome.storage.local
- `vpnProvider` - Access to the chrome.vpnProvider API
- `wallpaper` - Access to the chrome.wallpaper API
- `webNavigation` - Access to the chrome.webNavigation API
- `webRequest` - Access to the chrome.webRequest API
- `webRequestBlocking` - Allows blocking in webRequest

## Special Permissions

- `activeTab` - A special permission that provides limited, user-initiated access to the current tab without requiring broad host permissions
- `unlimitedStorage` - Allows the extension to exceed the normal storage quota limits

## User Experience

When an extension requests permissions:
1. Users see a permission warning during installation
2. The warning explains what access the extension will have
3. Users must accept these permissions to install the extension

## Best Practices

1. **Request only necessary permissions** - Only request permissions your extension actually needs
2. **Use activeTab when possible** - It provides temporary access without broad permissions
3. **Consider optional permissions** - Use `optional_permissions` for features that not all users need
4. **Provide clear explanations** - Help users understand why your extension needs specific permissions

## Example

```json
{
  "manifest_version": 3,
  "name": "My Extension",
  "version": "1.0",
  "permissions": [
    "storage",
    "tabs",
    "notifications"
  ]
}
```

## Security Considerations

- Permissions increase the attack surface of an extension
- Each permission should be justified by a specific feature
- Avoid requesting permissions "just in case" they might be needed
- Users are more likely to trust and install extensions with fewer permission requirements

## References

- [MDN Web Docs - permissions](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/permissions)
- [Chrome Developers - Declare permissions](https://developer.chrome.com/docs/extensions/mv3/declare_permissions/)