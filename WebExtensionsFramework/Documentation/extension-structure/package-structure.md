# WebExtension Package Structure

## Required Files
- **`manifest.json`** - Only mandatory file containing extension metadata

## Directory Structure & File Types

### Script Files
- **Background scripts** (`background.js`, service workers in V3)
- **Content scripts** (`.js` files injected into web pages)
- **Extension page scripts** (for popups, options, sidebars)

### Stylesheets
- **Content CSS** (`.css` files injected into web pages)
- **Extension page CSS** (for UI components)

### HTML Documents
- **Popup pages** (`popup.html`)
- **Options pages** (`options.html`)
- **Sidebar pages** (`sidebar.html`)
- **Background pages** (`background.html` in V2)
- **Extension pages** (any HTML with WebExtension API access)

### Assets
- **Icons** (`.png`, `.jpg`, `.svg` - various sizes: 16, 32, 48, 128px)
- **Images** (for web accessible resources)
- **Fonts** (if needed by extension UI)

### Localization
- **`_locales/` directory** containing locale-specific message files
- **`messages.json`** files in locale subdirectories

### Web Accessible Resources
- **Any file type** that needs to be accessible to web pages
- **Images, CSS, JS** that content scripts or web pages need to reference

### Data Files
- **JSON configuration files**
- **Text files, data files** as needed

## Reserved Names
- Files/directories starting with `_` are reserved for browser use
- `_locales/` is the standard localization directory

## Example Structure
```
my-extension/
├── manifest.json                 # Required
├── background.js                 # Background script
├── content.js                   # Content script
├── popup.html                   # Popup UI
├── popup.js                     # Popup script
├── options.html                 # Options page
├── styles.css                   # Extension CSS
├── icons/                       # Icon assets
│   ├── icon16.png
│   ├── icon32.png
│   ├── icon48.png
│   └── icon128.png
├── images/                      # Web accessible images
│   └── logo.png
├── _locales/                    # Localization
│   ├── en/
│   │   └── messages.json
│   └── es/
│       └── messages.json
└── lib/                         # Additional libraries
    └── utils.js
```

## Sources
- https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Anatomy_of_a_WebExtension
- https://w3c.github.io/webextensions/specification/index.html