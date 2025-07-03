# version

## Type
String

## Required
Yes

## Description
Version of the extension.

## Format
- 1 to 4 numbers separated by dots (e.g., "1.2.3.4")
- Non-zero numbers cannot have leading zeros
- Valid examples: "0.2", "2.0.1", "2.10"
- Invalid example: "2.01"

## Constraints
### Mozilla Add-ons (AMO)
- Allows up to 9-digit numbers
- Regex: `^(0|[1-9][0-9]{0,8})([.](0|[1-9][0-9]{0,8})){0,3}$`

### Chrome Web Store
- Requires numbers between 0-65535
- Prohibits all-zero version strings (e.g., "0.0" or "0.0.0.0")

## Version Comparison
- Compared left to right
- Missing elements treated as "0"
- Example: "1.10" is more recent than "1.9"

## Example
```json
"version": "1.0"
```

## Sources
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/version