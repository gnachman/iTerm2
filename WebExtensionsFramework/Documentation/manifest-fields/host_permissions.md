# host_permissions

The `host_permissions` field in Manifest V3 is used to request access to specific web origins (URLs) that the extension needs to interact with.

## Manifest Field

```json
{
  "host_permissions": [
    "https://example.com/*",
    "*://*.example.org/*"
  ]
}
```

- **Type**: Array of strings (match patterns)
- **Required**: No
- **Manifest Version**: 3

## Description

In Manifest V3, host permissions are separated from API permissions. The `host_permissions` field declares which web origins your extension can access. These permissions are required for APIs that read or modify host data, such as cookies, webRequest, and tabs APIs.

## Match Patterns

Host permissions use match patterns to specify which URLs the extension can access. A match pattern consists of:
- **Scheme**: `http`, `https`, `*` (matches both http and https)
- **Host**: Can include wildcards (`*.example.com`)
- **Path**: Can include wildcards

### Examples:
- `"https://example.com/*"` - All paths on example.com over HTTPS
- `"*://*.example.com/*"` - All subdomains of example.com over any protocol
- `"<all_urls>"` - Special pattern matching all URLs

## Privileges Granted

Host permissions provide access to:
- **Cross-origin requests** - XMLHttpRequest/fetch to the specified origins
- **Tab information** - Read sensitive tab properties (URL, title, favIconUrl)
- **Content script injection** - Programmatically inject scripts into pages
- **WebRequest API** - Intercept and modify network requests
- **Cookies API** - Access cookies for the specified domains
- **Bypass tracking protection** - For the specified origins

## User Control

Users can:
- Grant or revoke host permissions on an ad hoc basis
- Manage permissions through the browser's extension settings
- See which sites an extension has access to

## Browser Differences

- **Firefox (127+)**: Displays host permissions in the installation prompt
- **Chrome**: Displays host permissions in the installation prompt
- **Safari**: Does not display host permissions during installation

## Example

```json
{
  "manifest_version": 3,
  "name": "My Extension",
  "version": "1.0",
  "host_permissions": [
    "https://api.example.com/*",
    "*://localhost/*"
  ],
  "permissions": ["storage", "tabs"]
}
```

## Best Practices

1. **Request minimal origins** - Only request access to origins your extension actually needs
2. **Use specific patterns** - Avoid `<all_urls>` unless absolutely necessary
3. **Consider optional permissions** - Use `optional_host_permissions` for non-essential features
4. **Explain the need** - Make it clear why your extension needs access to specific sites

## Security Considerations

- Host permissions grant significant power over web content
- Each additional origin increases the potential attack surface
- Users may be hesitant to install extensions with broad host permissions
- Consider using more restrictive patterns when possible

## References

- [MDN Web Docs - host_permissions](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/host_permissions)
- [Chrome Developers - Host permissions](https://developer.chrome.com/docs/extensions/mv3/declare_permissions/#host-permissions)