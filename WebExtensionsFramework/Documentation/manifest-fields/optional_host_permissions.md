# optional_host_permissions

The `optional_host_permissions` field allows extensions to request access to additional web origins at runtime, after installation.

## Manifest Field

```json
{
  "optional_host_permissions": [
    "https://example.com/*",
    "*://*.example.org/*"
  ]
}
```

- **Type**: Array of strings (match patterns)
- **Required**: No
- **Manifest Version**: 3

## Description

Optional host permissions enable extensions to request access to specific web origins dynamically. This gives users more control by allowing them to grant access to websites only when needed, rather than requiring all host permissions at installation time.

## How It Works

1. Declare host patterns in `optional_host_permissions` in the manifest
2. Use the `permissions.request()` API to prompt the user at runtime
3. User can grant or deny access to the requested origins
4. Check granted permissions with `permissions.contains()`

## Match Patterns

Uses the same match pattern format as `host_permissions`:
- `"https://example.com/*"` - All paths on example.com over HTTPS
- `"*://*.example.com/*"` - All subdomains of example.com
- `"<all_urls>"` - All URLs (use sparingly)

## Runtime Request Example

```javascript
// Request host permission when needed
async function requestSiteAccess() {
  const granted = await chrome.permissions.request({
    origins: ['https://api.example.com/*']
  });
  
  if (granted) {
    // Permission granted, can now access the site
    fetchDataFromAPI();
  } else {
    // Permission denied, show alternative UI
    showPermissionDeniedMessage();
  }
}
```

## Example Manifest

```json
{
  "manifest_version": 3,
  "name": "My Extension",
  "version": "1.0",
  "host_permissions": [
    "https://myapp.com/*"
  ],
  "optional_host_permissions": [
    "https://*.github.com/*",
    "https://*.gitlab.com/*",
    "*://localhost/*"
  ]
}
```

## Checking Permissions

```javascript
// Check if permission is already granted
chrome.permissions.contains({
  origins: ['https://example.com/*']
}, (result) => {
  if (result) {
    // Permission already granted
  } else {
    // Need to request permission
  }
});
```

## User Experience

- Users see a prompt explaining which sites the extension wants to access
- The prompt appears similar to installation warnings
- Granted permissions persist across sessions
- Users can revoke access through browser extension settings
- Some browsers show which optional permissions are available

## Use Cases

1. **Multi-site support** - Support various services without requiring all permissions upfront
2. **User-configured integrations** - Let users choose which sites to integrate with
3. **Privacy-first approach** - Start with no host permissions, request as needed
4. **Enterprise features** - Optional access to internal company domains

## Best Practices

1. **Request in context** - Ask for permissions when users try to use the feature
2. **Explain the need** - Show why access to the site is required
3. **Handle denial** - Provide alternative functionality or clear messaging
4. **Remember user choice** - Don't repeatedly ask for denied permissions
5. **Minimal scope** - Request only the specific origins needed

## Combining with Regular Host Permissions

```json
{
  "host_permissions": [
    "https://api.myservice.com/*"  // Always needed
  ],
  "optional_host_permissions": [
    "https://*.customer-site.com/*"  // User-specific sites
  ]
}
```

## Security Considerations

- Optional host permissions have the same security implications as regular host permissions once granted
- Users maintain control over which sites extensions can access
- Extensions should validate and sanitize data from any accessed sites
- Consider the principle of least privilege

## Browser Differences

- Support and UI for optional host permissions may vary between browsers
- Some browsers may have different prompting mechanisms
- User settings interfaces differ across browsers

## References

- [MDN Web Docs - optional_host_permissions](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/optional_host_permissions)
- [Chrome Developers - Optional permissions](https://developer.chrome.com/docs/extensions/reference/permissions/)