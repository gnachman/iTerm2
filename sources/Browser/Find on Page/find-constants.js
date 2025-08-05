
// ==============================
//  Block-Based Find Engine
// ==============================

const TAG = '[iTermCustomFind-BlockBased]';
const sessionSecret = "{{SECRET}}";
const DEFAULT_INSTANCE_ID = 'default';

// Security constants
const MAX_SEARCH_TERM_LENGTH = 1000;
const MAX_CONTEXT_LENGTH = 500;
const MAX_REGEX_COMPLEXITY = 100;
const MAX_INSTANCES = 10;
const VALID_SEARCH_MODES = ['caseSensitive', 'caseInsensitive', 'caseSensitiveRegex', 'caseInsensitiveRegex'];
const VALID_ACTIONS = ['startFind', 'findNext', 'findPrevious', 'clearFind', 'reveal', 'hideResults', 'showResults'];

// Inject styles once
const highlightStyles = `
     .iterm-find-highlight {
         background-color: #FFFF00 !important;
         color: #000000 !important;
         border-radius: 2px;
     }
     .iterm-find-highlight-current {
         background-color: #FF9632 !important;
         color: #000000 !important;
         border-radius: 2px;
     }
     .iterm-find-highlight-current .iterm-find-highlight {
         background-color: #FF9632 !important;
         color: #000000 !important;
     }
     .iterm-find-removed {
         display: none !important;
     }
 `;
const SAFE_REVEAL_SELECTORS = [
    'details:not([open])',
    '.mw-collapsible.mw-collapsed',
    '.mw-collapsible:not(.mw-expanded)',
    'tr[hidden="until-found"]',
    '.accordion',
    '[aria-expanded="false"]',
    '[data-collapsed="true"]'
];
