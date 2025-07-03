# manifest_version

## Type
Number

## Required
Yes

## Description
Specifies the version of manifest.json used by this extension.

## Valid Values
- `3` - Manifest V3 (current standard)

## Example
```json
"manifest_version": 3
```

## Notes
- This field is mandatory in every WebExtensions manifest
- Determines the structure and capabilities available to the extension
- Must be exactly `3` for Manifest V3 extensions

## Sources
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/manifest_version