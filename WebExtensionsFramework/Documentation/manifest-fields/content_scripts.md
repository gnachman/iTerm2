# content_scripts

## Type
Array of Objects

## Required
No

## Description
Instructs the browser to load content scripts into web pages whose URL matches a pattern.

## Object Properties

### Required
- `matches`: Array of strings (match patterns)
  - URL patterns where scripts will be injected
  - At least one pattern required

### Optional
- `js`: Array of strings (file paths)
  - JavaScript files to inject
- `css`: Array of strings (file paths)
  - CSS files to inject
- `all_frames`: Boolean (default: false)
  - Whether to inject into all frames or just top frame
- `run_at`: String (default: "document_idle")
  - When to inject scripts
  - Options: "document_start", "document_end", "document_idle"
- `world`: String (default: "ISOLATED")
  - Script execution context
  - Options: "ISOLATED", "MAIN"
- `exclude_matches`: Array of strings (match patterns)
  - URL patterns to exclude from injection
- `include_globs`: Array of strings (glob patterns)
  - Additional glob patterns to include
- `exclude_globs`: Array of strings (glob patterns)
  - Glob patterns to exclude
- `match_about_blank`: Boolean
  - Whether to inject into about:blank pages
- `match_origin_as_fallback`: Boolean
  - Whether to inject into opaque origins

## Example
```json
"content_scripts": [{
  "matches": ["<all_urls>"],
  "js": ["content.js"],
  "run_at": "document_end"
}]
```

## Notes
- Scripts are injected in array order
- CSS is applied before JavaScript
- Each object represents a separate content script registration

## Sources
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/content_scripts