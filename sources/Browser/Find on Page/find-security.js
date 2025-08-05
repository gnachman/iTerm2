// ==============================
//  Security: Native API Capture
// ==============================

// Capture all native DOM APIs before any user code can tamper with them
const _createRange = document.createRange.bind(document);
const _createTreeWalker = document.createTreeWalker.bind(document);
const _createElement = document.createElement.bind(document);
const _querySelectorAll = document.querySelectorAll.bind(document);
const _getElementById = document.getElementById.bind(document);

// Range prototype methods
const _Range_setStart = Range.prototype.setStart;
const _Range_setEnd = Range.prototype.setEnd;
const _Range_extractContents = Range.prototype.extractContents;
const _Range_insertNode = Range.prototype.insertNode;
const _Range_surroundContents = Range.prototype.surroundContents;

// TreeWalker/NodeFilter
const _TreeWalker_nextNode = TreeWalker.prototype.nextNode;
const _SHOW_TEXT = NodeFilter.SHOW_TEXT;
const _FILTER_ACCEPT = NodeFilter.FILTER_ACCEPT;
const _FILTER_REJECT = NodeFilter.FILTER_REJECT;

// Element methods
const _matches = Element.prototype.matches;
const _getBoundingClientRect = Element.prototype.getBoundingClientRect;
const _scrollIntoView = Element.prototype.scrollIntoView;
const _appendChild = Element.prototype.appendChild;
const _insertBefore = Element.prototype.insertBefore;
const _removeChild = Element.prototype.removeChild;
const _setAttribute = Element.prototype.setAttribute;
const _getAttribute = Element.prototype.getAttribute;
const _removeAttribute = Element.prototype.removeAttribute;
const _hasAttribute = Element.prototype.hasAttribute;

// Node methods
const _normalize = Node.prototype.normalize;

// Window/Document methods
const _getComputedStyle = window.getComputedStyle;
const _addEventListener = EventTarget.prototype.addEventListener;
const _removeEventListener = EventTarget.prototype.removeEventListener;
const _caretRangeFromPoint = document.caretRangeFromPoint ? document.caretRangeFromPoint.bind(document) : null;

// Text node properties - capture descriptor to get native getter/setter
const _textContentDescriptor = Object.getOwnPropertyDescriptor(Node.prototype, 'textContent');
const _textContentGetter = _textContentDescriptor ? _textContentDescriptor.get : null;

// ClassList methods
const _classList_add = DOMTokenList.prototype.add;
const _classList_remove = DOMTokenList.prototype.remove;
const _classList_contains = DOMTokenList.prototype.contains;

// RegExp methods
const _RegExp_exec = RegExp.prototype.exec;

// JSON methods
const _JSON_stringify = JSON.stringify;

// Freeze critical prototypes to prevent tampering after our capture
Object.freeze(document.createRange);
Object.freeze(document.createTreeWalker);
Object.freeze(Range.prototype.setStart);
Object.freeze(Range.prototype.setEnd);
Object.freeze(Range.prototype.extractContents);
Object.freeze(Range.prototype.insertNode);
Object.freeze(TreeWalker.prototype.nextNode);
Object.freeze(Element.prototype.matches);
Object.freeze(Element.prototype.getBoundingClientRect);
Object.freeze(Element.prototype.appendChild);
Object.freeze(Element.prototype.insertBefore);
Object.freeze(Element.prototype.removeChild);
Object.freeze(Element.prototype.setAttribute);
Object.freeze(Element.prototype.getAttribute);
Object.freeze(Element.prototype.removeAttribute);
Object.freeze(Element.prototype.hasAttribute);
Object.freeze(Element.prototype.scrollIntoView);
Object.freeze(Node.prototype.removeChild);
Object.freeze(Node.prototype.normalize);
Object.freeze(DOMTokenList.prototype.add);
Object.freeze(DOMTokenList.prototype.remove);
Object.freeze(DOMTokenList.prototype.contains);
Object.freeze(RegExp.prototype.exec);
Object.freeze(JSON.stringify);
Object.freeze(window.getComputedStyle);

// Message handler capture (done early to prevent tampering)
const _messageHandler = window.webkit?.messageHandlers?.iTermCustomFind;
const _postMessage = _messageHandler?.postMessage?.bind(_messageHandler);
