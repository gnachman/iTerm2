# name

## Type
String

## Required
Yes

## Description
Name of the extension. This is used to identify the extension in the browser's user interface.

## Constraints
- Recommended to keep short enough to display in UI
- Store-specific maximums:
  - addons.mozilla.org: 50 characters
  - Chrome Web Store: 75 characters
  - Microsoft Edge Addons: 45 characters
- These length restrictions do not apply to self-hosted extensions

## Example
```json
"name": "My Extension"
```

## Notes
- This field is localizable (can be translated)
- Used for display in browser UI and extension management

## Sources
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/name