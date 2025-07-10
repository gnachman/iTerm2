# optional_permissions

The `optional_permissions` field allows extensions to request additional API permissions at runtime, after installation.

## Manifest Field

```json
{
  "optional_permissions": ["permission1", "permission2", ...]
}
```

- **Type**: Array of strings
- **Required**: No
- **Manifest Version**: 3

## Description

Optional permissions enable extensions to request additional capabilities dynamically, giving users more control over what access they grant. Unlike regular permissions which must be accepted during installation, optional permissions can be requested when specific features are needed.

## How It Works

1. Declare permissions in `optional_permissions` in the manifest
2. Use the `permissions.request()` API to prompt the user at runtime
3. User can grant or deny the requested permissions
4. Check granted permissions with `permissions.contains()`

## Available Optional Permissions

Most API permissions can be optional, including:
- `activeTab`
- `bookmarks`
- `clipboardRead`
- `clipboardWrite`
- `cookies`
- `debugger`
- `downloads`
- `history`
- `management`
- `notifications`
- `storage`
- `tabs`
- `topSites`
- `webNavigation`
- `webRequest`
- `webRequestBlocking`

Note: Some permissions cannot be optional and must be declared in the regular `permissions` field.

## Runtime Request Example

```javascript
// Request permission when user clicks a button
document.getElementById('enable-feature').addEventListener('click', () => {
  chrome.permissions.request(
    { permissions: ['bookmarks'] },
    (granted) => {
      if (granted) {
        // Permission was granted, enable the feature
        enableBookmarksFeature();
      } else {
        // Permission was denied
        console.log('Permission denied');
      }
    }
  );
});
```

## Example Manifest

```json
{
  "manifest_version": 3,
  "name": "My Extension",
  "version": "1.0",
  "permissions": ["storage"],
  "optional_permissions": [
    "bookmarks",
    "history",
    "tabs"
  ]
}
```

## User Experience

- Permissions requested at runtime show a prompt similar to installation
- Users can grant or deny each request
- Granted optional permissions persist across browser sessions
- Users can revoke optional permissions in browser settings

## Browser Support

- **Chrome**: Full support
- **Firefox**: Supported, with UI in Add-ons Manager (Firefox 84+)
- **Safari**: Limited support

Some browsers may grant certain optional permissions silently without user prompt.

## Best Practices

1. **Progressive enhancement** - Core features should work without optional permissions
2. **Context-aware requests** - Request permissions when users try to use related features
3. **Clear communication** - Explain why the permission is needed before requesting
4. **Graceful degradation** - Handle permission denial gracefully
5. **Check before use** - Always verify permissions before using APIs

## Use Cases

- **Feature flags** - Enable advanced features for users who want them
- **Privacy-conscious design** - Start with minimal permissions
- **Reducing installation friction** - Lower barrier to initial installation
- **Modular functionality** - Different features require different permissions

## Security Considerations

- Optional permissions still require user consent
- Once granted, they have the same power as regular permissions
- Users can revoke permissions at any time
- Extensions should handle revoked permissions gracefully

## References

- [MDN Web Docs - optional_permissions](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/optional_permissions)
- [Chrome Developers - Optional permissions](https://developer.chrome.com/docs/extensions/reference/permissions/)