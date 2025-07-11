# Storage API

The Storage API provides extensions with the ability to store and retrieve data across browser sessions. This API is essential for maintaining user preferences, extension state, and other persistent data.

## Permission Required

To use the Storage API, extensions must include the `"storage"` permission in their manifest:

```json
{
  "permissions": ["storage"]
}
```

## Storage Areas

The Storage API provides four distinct storage areas:

### storage.local
- **Purpose**: Machine-specific storage that persists locally
- **Quota**: 10MB
- **Persistence**: Data survives extension removal and browser restarts
- **Accessibility**: Available to content scripts
- **Use case**: Large datasets, user preferences, cached data

### storage.sync
- **Purpose**: Chrome Sync-enabled storage that syncs across devices
- **Quota**: 100KB total, 8KB per item, maximum 512 items
- **Persistence**: Syncs across user's Chrome browsers
- **Use case**: User settings and preferences that should follow the user

### storage.session
- **Purpose**: In-memory storage for temporary data
- **Quota**: 10MB
- **Persistence**: Cleared when browser is restarted
- **Accessibility**: Not exposed to content scripts by default
- **Use case**: Temporary state, session-specific data

### storage.managed
- **Purpose**: Read-only storage managed by enterprise policies
- **Access**: Read-only for extensions
- **Use case**: Enterprise-configured settings

## API Methods

All storage methods are asynchronous and return Promises.

### get(keys)
Retrieves items from storage.

```javascript
// Get a single item
chrome.storage.local.get(['key1']).then((result) => {
  console.log('Value is', result.key1);
});

// Get multiple items
chrome.storage.local.get(['key1', 'key2']).then((result) => {
  console.log(result);
});

// Get all items
chrome.storage.local.get().then((result) => {
  console.log(result);
});
```

### set(items)
Stores items in storage.

```javascript
chrome.storage.local.set({
  key1: 'value1',
  key2: { nested: 'object' }
}).then(() => {
  console.log('Values are set');
});
```

### remove(keys)
Removes items from storage.

```javascript
// Remove single item
chrome.storage.local.remove(['key1']).then(() => {
  console.log('Item removed');
});

// Remove multiple items
chrome.storage.local.remove(['key1', 'key2']).then(() => {
  console.log('Items removed');
});
```

### clear()
Removes all items from storage.

```javascript
chrome.storage.local.clear().then(() => {
  console.log('All items cleared');
});
```

## Event Listeners

### onChanged
Fired when storage items are modified.

```javascript
chrome.storage.onChanged.addListener((changes, areaName) => {
  for (let [key, { oldValue, newValue }] of Object.entries(changes)) {
    console.log(
      `Storage key "${key}" in namespace "${areaName}" changed.`,
      `Old value was "${oldValue}", new value is "${newValue}".`
    );
  }
});
```

## Data Types and Limitations

- **Supported types**: JSON-serializable values (strings, numbers, booleans, arrays, objects)
- **Unsupported types**: Functions, DOM nodes, undefined values
- **Security**: Storage is not encrypted and should not contain sensitive information
- **Scope**: Data is scoped to the entire extension (shared across all extension contexts)

## Error Handling

Storage operations can fail due to quota limits, invalid data, or system issues:

```javascript
chrome.storage.local.set({ key: 'value' }).catch((error) => {
  console.error('Storage operation failed:', error);
});
```

## Best Practices

1. **Use appropriate storage area**: Choose based on data persistence and sync requirements
2. **Handle errors**: Always include error handling for storage operations
3. **Respect quotas**: Monitor storage usage to avoid quota exceeded errors
4. **JSON compatibility**: Ensure all stored data is JSON-serializable
5. **Security**: Never store sensitive information like passwords or tokens