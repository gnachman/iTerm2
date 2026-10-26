// The body of a function that reports, for iTerm2 Buddy, whether the page's
// focused element is a text editor and where its insertion point is.
//
// While someone is using the phone, the browser's window on the Mac is usually
// not the key window. Then the editing detector (which requires
// document.hasFocus()) reports false and WebKit does not draw the insertion
// point, so this looks at the focused element directly and measures where the
// insertion point would be so the Mac can draw it into the streamed frames.
//
// Returns {editing, focused, caret}. `focused` is document.hasFocus(); when it
// is true WebKit draws its own insertion point and `caret` is null. Otherwise
// `caret` is null or {x, y, height, color}, with x, y, and height as fractions
// of the visible viewport and color as a CSS color. Focus inside a cross-origin
// frame is not visible from here.
const result = { editing: false, focused: document.hasFocus(), caret: null };

function lineMetrics(style) {
    const fontSize = parseFloat(style.fontSize) || 16;
    const lineHeight = parseFloat(style.lineHeight);
    const height = fontSize * 1.2;
    return { height: height, lineHeight: isNaN(lineHeight) ? height : lineHeight };
}

function caretColor(style) {
    const color = style.caretColor;
    return (!color || color === "auto") ? style.color : color;
}

// Styles that affect where text lays out in a text field, copied to the mirror.
const mirroredProperties = [
    "direction", "boxSizing", "width", "height", "overflowX", "overflowY",
    "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth", "borderStyle",
    "paddingTop", "paddingRight", "paddingBottom", "paddingLeft",
    "fontStyle", "fontVariant", "fontWeight", "fontStretch", "fontSize", "fontSizeAdjust",
    "lineHeight", "fontFamily", "fontFeatureSettings", "fontKerning",
    "textAlign", "textTransform", "textIndent", "textDecoration",
    "letterSpacing", "wordSpacing", "tabSize"
];

// Where the insertion point of an input or textarea is, relative to its border
// box. The field does not expose this, so lay its text out in a hidden copy
// with the same styles and measure there. Measuring changes the DOM, so the
// result is cached until something that affects it changes.
function fieldCaretOffset(el, doc, style, isInput) {
    const pos = el.selectionEnd;
    const key = [el.value, pos, el.clientWidth, el.clientHeight, style.font, style.letterSpacing].join("\u0000");
    const cache = globalThis.__iTerm2CompanionCaretCache;
    if (cache && cache.key === key && cache.element.deref() === el) {
        return cache.offset;
    }
    const mirror = doc.createElement("div");
    for (const property of mirroredProperties) {
        mirror.style[property] = style[property];
    }
    mirror.style.position = "absolute";
    mirror.style.visibility = "hidden";
    mirror.style.top = "0";
    mirror.style.left = "-9999px";
    mirror.style.overflow = "hidden";
    if (isInput) {
        mirror.style.whiteSpace = "pre";
    } else {
        mirror.style.whiteSpace = "pre-wrap";
        mirror.style.overflowWrap = "break-word";
        if (el.scrollHeight > el.clientHeight) {
            mirror.style.overflowY = "scroll";
        }
    }
    const before = el.value.substring(0, pos);
    mirror.textContent = isInput ? before.replace(/\s/g, " ") : before;
    const marker = doc.createElement("span");
    // The rest of the text makes the marker wrap the way the field does.
    marker.textContent = el.value.substring(pos) || ".";
    mirror.appendChild(marker);
    (doc.body || doc.documentElement).appendChild(mirror);
    const offset = {
        left: marker.offsetLeft + (parseFloat(style.borderLeftWidth) || 0),
        top: marker.offsetTop + (parseFloat(style.borderTopWidth) || 0)
    };
    mirror.remove();
    globalThis.__iTerm2CompanionCaretCache = { key: key, element: new WeakRef(el), offset: offset };
    return offset;
}

function fieldCaret(el, doc, isInput) {
    let start, end;
    try {
        start = el.selectionStart;
        end = el.selectionEnd;
    } catch (_) {
        return null;
    }
    // A range selection has no insertion point.
    if (start === null || start !== end) {
        return null;
    }
    const style = doc.defaultView.getComputedStyle(el);
    const offset = fieldCaretOffset(el, doc, style, isInput);
    const rect = el.getBoundingClientRect();
    const metrics = lineMetrics(style);
    const x = rect.left + offset.left - el.scrollLeft;
    let y;
    if (isInput) {
        // An input centers its line vertically.
        y = rect.top + (rect.height - metrics.height) / 2;
    } else {
        y = rect.top + offset.top - el.scrollTop + (metrics.lineHeight - metrics.height) / 2;
    }
    // Hidden when scrolled out of the field.
    if (x < rect.left || x > rect.right || y + metrics.height < rect.top || y > rect.bottom) {
        return null;
    }
    return { left: x, top: y, height: metrics.height, color: caretColor(style) };
}

function selectionCaret(doc) {
    const selection = doc.defaultView.getSelection();
    if (!selection || selection.rangeCount === 0 || !selection.isCollapsed) {
        return null;
    }
    const node = selection.focusNode;
    let element = node && node.nodeType === Node.ELEMENT_NODE ? node : node && node.parentElement;
    if (!element) {
        return null;
    }
    const range = selection.getRangeAt(0).cloneRange();
    const rects = range.getClientRects();
    let rect = rects.length > 0 ? rects[0] : range.getBoundingClientRect();
    let style = doc.defaultView.getComputedStyle(element);
    let metrics = lineMetrics(style);
    if (rect && rect.height > 0) {
        return {
            left: rect.left,
            top: rect.top + (rect.height - metrics.height) / 2,
            height: metrics.height,
            color: caretColor(style)
        };
    }
    // An empty line has no text to measure, so use the start of its element.
    const child = node.nodeType === Node.ELEMENT_NODE ? node.childNodes[selection.focusOffset] : null;
    if (child && child.nodeType === Node.ELEMENT_NODE) {
        element = child;
        style = doc.defaultView.getComputedStyle(element);
        metrics = lineMetrics(style);
    }
    const box = element.getBoundingClientRect();
    return {
        left: box.left + (parseFloat(style.borderLeftWidth) || 0) + (parseFloat(style.paddingLeft) || 0),
        top: box.top + (parseFloat(style.borderTopWidth) || 0) + (parseFloat(style.paddingTop) || 0)
            + (metrics.lineHeight - metrics.height) / 2,
        height: metrics.height,
        color: caretColor(style)
    };
}

const textInputTypes = ["text", "search", "url", "tel", "email", "password", "number"];

// Find the focused element, through shadow roots and same-origin frames,
// keeping track of where the frames are in the top document.
let doc = document;
let el = doc.activeElement;
let frameX = 0;
let frameY = 0;
while (el) {
    if (el.shadowRoot && el.shadowRoot.activeElement) {
        el = el.shadowRoot.activeElement;
        continue;
    }
    const tag = el.tagName ? el.tagName.toLowerCase() : "";
    if (tag !== "iframe" && tag !== "frame") {
        break;
    }
    let inner = null;
    try {
        inner = el.contentDocument;
    } catch (_) {
    }
    if (!inner) {
        return result;
    }
    const frameRect = el.getBoundingClientRect();
    frameX += frameRect.left + el.clientLeft;
    frameY += frameRect.top + el.clientTop;
    doc = inner;
    el = inner.activeElement;
}

let kind = null;
if (String(doc.designMode).toLowerCase() === "on") {
    kind = "selection";
} else if (!el || el === doc.body) {
    if (doc.body && doc.body.isContentEditable) {
        kind = "selection";
    }
} else if (el.isContentEditable) {
    kind = "selection";
} else {
    const tag = el.tagName ? el.tagName.toLowerCase() : "";
    const writable = !el.readOnly && !el.disabled;
    if (tag === "textarea" && writable) {
        kind = "textarea";
    } else if (tag === "input" && writable &&
               textInputTypes.includes((el.getAttribute("type") || "text").toLowerCase())) {
        kind = "input";
    }
}
if (!kind) {
    return result;
}
result.editing = true;
if (result.focused) {
    return result;
}

const caret = kind === "selection" ? selectionCaret(doc) : fieldCaret(el, doc, kind === "input");
if (!caret) {
    return result;
}
// Convert from the top document's CSS pixels to fractions of what is on
// screen, which accounts for page zoom and pinch magnification.
const viewport = window.visualViewport;
const scale = viewport ? viewport.scale : 1;
const offsetLeft = viewport ? viewport.offsetLeft : 0;
const offsetTop = viewport ? viewport.offsetTop : 0;
const width = window.innerWidth;
const height = window.innerHeight;
if (!(width > 0) || !(height > 0)) {
    return result;
}
const x = (frameX + caret.left - offsetLeft) * scale / width;
const y = (frameY + caret.top - offsetTop) * scale / height;
const h = caret.height * scale / height;
if (x < 0 || x > 1 || y + h < 0 || y > 1) {
    return result;
}
result.caret = { x: x, y: y, height: h, color: caret.color };
return result;
