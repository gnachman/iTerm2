// Per-frame singleton installed by injected snippets
function ensureFrameStore() {
    if (!window.__iTermFormStore) {
        const elToId = new WeakMap();
        const idToEl = new Map();
        const counters = { next: 1 };
        function randHex32() {
            // 16 bytes -> 32 hex chars
            const a = new Uint8Array(16);
            (window.crypto || {}).getRandomValues ? crypto.getRandomValues(a) : (() => {
                for (let i = 0; i < a.length; i += 1) { a[i] = (Math.random() * 256) | 0; }
            })();
            let s = "";
            for (let i = 0; i < a.length; i += 1) {
                s += a[i].toString(16).padStart(2, "0");
            }
            return s;
        }
        function idFor(el) {
            if (!el) { return null; }
            let id = elToId.get(el);
            if (id) { return id; }
            id = randHex32();
            elToId.set(el, id);
            idToEl.set(id, el);
            return id;
        }
        function elFor(id) {
            return idToEl.get(id) || null;
        }
        function forget(id) {
            const el = idToEl.get(id);
            if (el) {
                idToEl.delete(id);
                // WeakMap will forget automatically
            }
        }
        window.__iTermFormStore = { idFor, elFor, forget, _elToId: elToId, _idToEl: idToEl, _counters: counters };
    }
    return window.__iTermFormStore;
}

function isVisible(el) {
    if (!el || !(el instanceof Element)) { return false; }
    const style = el.ownerDocument.defaultView.getComputedStyle(el);
    if (style.display === "none" || style.visibility === "hidden" || parseFloat(style.opacity || "1") === 0) {
        return false;
    }
    const rect = el.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) { return false; }
    // Check if in viewport-ish (allow partially offscreen)
    const vw = window.innerWidth || 0;
    const vh = window.innerHeight || 0;
    if (vw && vh) {
        if (rect.right < -1 || rect.bottom < -1 || rect.left > vw + 1 || rect.top > vh + 1) {
            // Might be scrolled out; still consider "potentially interactable"
            // We treat as visible but off-screen; caller may scrollIntoView.
            return true;
        }
    }
    return true;
}

function bbox(el) {
    const r = el.getBoundingClientRect();
    return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) };
}

function controlKind(el) {
    if (!el) { return "unknown"; }
    const tn = el.tagName.toLowerCase();
    if (tn === "textarea") { return "textarea"; }
    if (tn === "select") {
        return el.multiple ? "select-multiple" : "select-one";
    }
    if (tn === "input") {
        const t = (el.type || "text").toLowerCase();
        const map = {
            text: "text",
            search: "search",
            email: "email",
            url: "url",
            tel: "tel",
            number: "number",
            password: "password",
            date: "date",
            time: "time",
            "datetime-local": "datetime-local",
            month: "month",
            week: "week",
            checkbox: "checkbox",
            radio: "radio",
            file: "file",
            hidden: "hidden"
        };
        return map[t] || "text";
    }
    return "unknown";
}

function labelsFor(el) {
    try {
        const out = new Set();
        // <label for> + implicit label parent
        if (typeof el.labels !== "undefined" && el.labels) {
            for (const lab of el.labels) {
                if (lab && lab.textContent) {
                    out.add(lab.textContent.trim());
                }
            }
        }
        // aria-labelledby
        const ids = (el.getAttribute("aria-labelledby") || "").split(/\s+/).filter(Boolean);
        for (const id of ids) {
            const n = el.ownerDocument.getElementById(id);
            if (n && n.textContent) {
                out.add(n.textContent.trim());
            }
        }
        // aria-label
        const aria = el.getAttribute("aria-label");
        if (aria) { out.add(aria); }
        return Array.from(out);
    } catch (e) {
        return [];
    }
}

function placeholderFor(el) {
    return el.getAttribute && el.getAttribute("placeholder") || null;
}

function autocompleteFor(el) {
    return el.getAttribute && el.getAttribute("autocomplete") || null;
}

function valuePreview(el) {
    const k = controlKind(el);
    if (k === "password") { return null; }
    if (k === "checkbox" || k === "radio") {
        return !!el.checked;
    }
    if (k === "select-one") {
        const opt = el.selectedOptions && el.selectedOptions[0];
        return opt ? opt.value : null;
    }
    if (k === "select-multiple") {
        const vals = [];
        if (el.selectedOptions) {
            for (const o of el.selectedOptions) {
                vals.push(o.value);
            }
        }
        return vals;
    }
    return el.value != null ? String(el.value) : null;
}

function optionsFor(selectEl) {
    const opts = [];
    if (!selectEl || selectEl.tagName.toLowerCase() !== "select") { return opts; }
    for (const o of selectEl.options) {
        opts.push({
            value: o.value,
            label: o.label || o.textContent || "",
            selected: !!o.selected,
            disabled: !!o.disabled,
            group_label: o.parentElement && o.parentElement.tagName.toLowerCase() === "optgroup" ? (o.parentElement.label || null) : null
        });
    }
    return opts;
}

function hintTextFor(el) {
    const out = new Set();
    const describedBy = (el.getAttribute("aria-describedby") || "").split(/\s+/).filter(Boolean);
    for (const id of describedBy) {
        const n = el.ownerDocument.getElementById(id);
        if (n && n.textContent) {
            out.add(n.textContent.trim());
        }
    }
    return Array.from(out);
}

function radioGroupName(el) {
    if (controlKind(el) !== "radio") { return null; }
    return el.name || null;
}

function getForms(visibilityFilter /* "visible"|"any" */) {
    console.log("[agent-utils] getForms called with visibilityFilter:", visibilityFilter);
    const store = ensureFrameStore();
    const out = [];
    const doc = document;
    const forms = Array.from(doc.forms || []);
    console.log("[agent-utils] getForms: found", forms.length, "forms in document");
    for (const f of forms) {
        const visible = isVisible(f);
        if (visibilityFilter === "visible" && !visible) {
            continue;
        }
        const controls = [];
        const elems = Array.from(f.elements || []);
        for (const el of elems) {
            if (!(el instanceof HTMLElement)) { continue; }
            const kind = controlKind(el);
            if (kind === "hidden" || kind === "unknown") {
                continue;
            }
            controls.push({
                field_id: store.idFor(el),
                kind: kind,
                name: el.name || null,
                labels: labelsFor(el),
                placeholder: placeholderFor(el),
                autocomplete: autocompleteFor(el),
                required: !!el.required,
                disabled: !!el.disabled,
                read_only: !!el.readOnly,
                value_preview: valuePreview(el),
                visible: isVisible(el)
            });
        }
        const formData = {
            form_id: store.idFor(f),
            method: (f.method || "").toUpperCase() || null,
            action_url: f.getAttribute("action") || null,
            has_novalidate: f.noValidate === true,
            bbox_css_px: bbox(f),
            controls: controls
        };
        console.log("[agent-utils] getForms: processed form", formData.form_id, "with", controls.length, "controls");
        out.push(formData);
    }
    console.log("[agent-utils] getForms: returning", out.length, "forms");
    return out;
}

function describeForm(formId, includeOptions, includeAria, includeCss) {
    const store = ensureFrameStore();
    const f = store.elFor(formId);
    if (!f || !(f instanceof HTMLFormElement)) {
        return { error: { code: "not_found", message: "Form not found or detached" } };
    }
    const controls = [];
    for (const el of Array.from(f.elements || [])) {
        if (!(el instanceof HTMLElement)) { continue; }
        const kind = controlKind(el);
        if (kind === "hidden" || kind === "unknown") { continue; }
        controls.push({
            field_id: store.idFor(el),
            kind: kind,
            min: ("min" in el && el.min !== "") ? el.min : null,
            max: ("max" in el && el.max !== "") ? el.max : null,
            minlength: ("minLength" in el && el.minLength >= 0) ? el.minLength : null,
            maxlength: ("maxLength" in el && el.maxLength >= 0) ? el.maxLength : null,
            pattern: ("pattern" in el && el.pattern) ? el.pattern : null,
            step: ("step" in el && el.step) ? el.step : null,
            accept: (kind === "file" && el.accept) ? el.accept : null,
            options: includeOptions && (kind === "select-one" || kind === "select-multiple") ? optionsFor(el) : [],
            radio_group: radioGroupName(el),
            checked: (kind === "checkbox" || kind === "radio") ? !!el.checked : null,
            hint_text: includeAria ? hintTextFor(el) : [],
            bbox_css_px: bbox(el)
        });
    }
    // Basic heuristic role
    const role = (() => {
        const txt = (f.outerHTML || "").toLowerCase();
        if (txt.includes("login") || txt.includes("signin")) { return "login"; }
        if (txt.includes("signup") || txt.includes("register")) { return "signup"; }
        if (txt.includes("search")) { return "search"; }
        if (txt.includes("contact")) { return "contact"; }
        if (txt.includes("checkout")) { return "checkout"; }
        return "unknown";
    })();

    // Constraint validation snapshot
    const validity = f.checkValidity();
    const invalidReasons = [];
    if (!validity) {
        for (const el of Array.from(f.elements || [])) {
            if (el instanceof HTMLElement && "validity" in el && el.validity && !el.validity.valid) {
                invalidReasons.push(el.validationMessage || "invalid");
            }
        }
    }

    return {
        form_id: store.idFor(f),
        heuristic_role: role,
        constraints: { can_submit: !!validity, invalid_reasons: invalidReasons },
        controls: controls
    };
}

function currentFormValues(formId, maskSecrets) {
    const store = ensureFrameStore();
    const f = store.elFor(formId);
    if (!f || !(f instanceof HTMLFormElement)) {
        return { error: { code: "not_found", message: "Form not found or detached" } };
    }
    const vals = [];
    for (const el of Array.from(f.elements || [])) {
        if (!(el instanceof HTMLElement)) { continue; }
        const kind = controlKind(el);
        if (kind === "hidden" || kind === "unknown") { continue; }
        let value = null;
        if (kind === "checkbox" || kind === "radio") {
            value = !!el.checked;
        } else if (kind === "select-one") {
            const opt = el.selectedOptions && el.selectedOptions[0];
            value = opt ? opt.value : null;
        } else if (kind === "select-multiple") {
            value = Array.from(el.selectedOptions || []).map(o => o.value);
        } else {
            value = el.value != null ? String(el.value) : null;
        }
        if (maskSecrets && (kind === "password" || (el.autocomplete || "").includes("one-time-code"))) {
            value = value == null ? null : "••••";
        }
        vals.push({ field_id: store.idFor(el), value: value, is_dirty: !!el.matches(":user-invalid, :placeholder-shown") });
    }
    return { values: vals };
}

function setValue(fieldId, encoded) {
    console.log("[agent-utils] setValue called with fieldId:", fieldId, "encoded:", encoded);
    const store = ensureFrameStore();
    const el = store.elFor(fieldId);
    if (!el || !(el instanceof HTMLElement)) {
        console.error("[agent-utils] setValue: field not found:", fieldId);
        return { error: { code: "not_found", message: "Field not found or detached" } };
    }
    console.log("[agent-utils] setValue: found element", el.tagName, el.type);
    const k = controlKind(el);
    function fire(type, props) {
        const ev = new Event(type, Object.assign({ bubbles: true, cancelable: type !== "input" ? true : false }, props || {}));
        el.dispatchEvent(ev);
    }
    function apply(v) {
        if (k === "checkbox" || k === "radio") {
            el.checked = !!v;
        } else if (k === "select-one") {
            el.value = v == null ? "" : String(v);
        } else if (k === "select-multiple") {
            const want = new Set(Array.isArray(v) ? v.map(x => String(x)) : []);
            for (const o of el.options) { o.selected = want.has(o.value); }
        } else {
            el.value = v == null ? "" : String(v);
        }
    }

    const mode = encoded.mode || "set"; // "type" | "set" | "paste"
    const clearFirst = !!encoded.clearFirst;
    const ensureVisibleFlag = !!encoded.ensureVisible;
    const selectAfter = !!encoded.selectAfter;

    if (ensureVisibleFlag && el.scrollIntoView) {
        try { el.scrollIntoView({ block: "nearest", inline: "nearest" }); } catch (_) {}
    }
    if (document.activeElement !== el && el.focus) { try { el.focus(); fire("focus"); } catch (_) {} }

    if (mode === "type") {
        if (clearFirst) {
            el.value = "";
            fire("input");
        }
        const text = encoded.value == null ? "" : (Array.isArray(encoded.value) ? encoded.value.join("") : String(encoded.value));
        // Simulate as a single input event (char-by-char delays are intentionally skipped to avoid long waits)
        const prev = el.value || "";
        el.value = prev + text;
        fire("input");
        fire("change");
    } else if (mode === "paste") {
        const text = encoded.value == null ? "" : String(encoded.value);
        // Dispatch beforeinput with inputType="insertFromPaste"
        try {
            const ev = new InputEvent("beforeinput", { bubbles: true, cancelable: true, inputType: "insertFromPaste", data: text });
            el.dispatchEvent(ev);
        } catch (_) {}
        if (clearFirst) { el.value = ""; }
        el.value = text;
        fire("input");
        fire("change");
    } else {
        if (clearFirst) { el.value = ""; }
        apply(encoded.value);
        fire("input");
        fire("change");
    }

    if (selectAfter && el.select) { try { el.select(); } catch (_) {} }

    const result = {
        field_id: fieldId,
        applied_value_preview: valuePreview(el),
        fired_events: ["focus", "input", "change"],
        valid: ("checkValidity" in el) ? el.checkValidity() : true,
        invalid_reasons: ("validationMessage" in el && !el.checkValidity()) ? [el.validationMessage] : []
    };
    console.log("[agent-utils] setValue: result:", result);
    return result;
}

function choose(selectFieldId, by, choice, deselectOthers) {
    const store = ensureFrameStore();
    const el = store.elFor(selectFieldId);
    if (!el) { return { error: { code: "not_found", message: "Field not found or detached" } }; }
    const k = controlKind(el);
    if (!(k === "select-one" || k === "select-multiple" || k === "radio")) {
        return { error: { code: "unsupported", message: "Not a selectable control" } };
    }
    if (k === "radio") {
        const name = el.name || "";
        const form = el.form || el.ownerDocument;
        const radios = Array.from(form.querySelectorAll(`input[type="radio"][name="${CSS.escape(name)}"]`));
        function match(r) {
            if (by === "value") { return r.value === String(choice); }
            if (by === "label") { return labelsFor(r).some(l => l === String(choice)); }
            if (by === "index") { return Number(choice) === radios.indexOf(r); }
            return false;
        }
        let found = false;
        for (const r of radios) {
            if (match(r)) {
                r.checked = true;
                r.dispatchEvent(new Event("input", { bubbles: true }));
                r.dispatchEvent(new Event("change", { bubbles: true }));
                found = true;
                break;
            }
        }
        if (!found) { return { error: { code: "not_found", message: "Radio choice not found" } }; }
        return { field_id: selectFieldId, selected: radios.filter(r => r.checked).map(r => r.value), valid: el.checkValidity ? el.checkValidity() : true };
    }

    // select element
    const opts = Array.from(el.options || []);
    const wantVals = new Set();
    if (Array.isArray(choice)) {
        for (const v of choice) { wantVals.add(String(v)); }
    } else {
        wantVals.add(String(choice));
    }
    let matched = 0;
    function matchesOption(o) {
        if (by === "value") { return wantVals.has(o.value); }
        if (by === "label") { return wantVals.has(o.label || o.textContent || ""); }
        if (by === "index") {
            for (const v of wantVals) { if (Number(v) === opts.indexOf(o)) { return true; } }
            return false;
        }
        return false;
    }
    if (k === "select-one") {
        const target = opts.find(matchesOption);
        if (!target) { return { error: { code: "not_found", message: "Option not found" } }; }
        el.value = target.value;
        matched = 1;
    } else {
        if (deselectOthers) {
            for (const o of opts) { o.selected = false; }
        }
        for (const o of opts) {
            if (matchesOption(o)) {
                o.selected = true;
                matched += 1;
            }
        }
        if (matched === 0) { return { error: { code: "not_found", message: "No matching options" } }; }
    }
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    const selectedVals = Array.from(el.selectedOptions || []).map(o => o.value);
    return { field_id: selectFieldId, selected: selectedVals, valid: el.checkValidity ? el.checkValidity() : true };
}

function setCheckbox(fieldId, checked) {
    const store = ensureFrameStore();
    const el = store.elFor(fieldId);
    if (!el) { return { error: { code: "not_found", message: "Field not found or detached" } }; }
    if (controlKind(el) !== "checkbox") {
        return { error: { code: "unsupported", message: "Not a checkbox" } };
    }
    el.checked = !!checked;
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    return { field_id: fieldId, checked: !!el.checked };
}

function clickNode(nodeId, button, clickCount, ensureVisibleFlag) {
    const store = ensureFrameStore();
    const el = store.elFor(nodeId);
    if (!el || !(el instanceof HTMLElement)) {
        return { error: { code: "not_found", message: "Node not found or detached" } };
    }
    if (ensureVisibleFlag && el.scrollIntoView) {
        try { el.scrollIntoView({ block: "nearest", inline: "nearest" }); } catch (_) {}
    }
    const rect = el.getBoundingClientRect();
    const x = Math.max(0, Math.min(rect.width - 1, rect.width / 2));
    const y = Math.max(0, Math.min(rect.height - 1, rect.height / 2));
    const btnMap = { left: 0, middle: 1, right: 2 };
    const btn = btnMap[button] ?? 0;
    const init = { bubbles: true, cancelable: true, clientX: rect.left + x, clientY: rect.top + y, button: btn };
    el.dispatchEvent(new MouseEvent("mousemove", init));
    for (let i = 0; i < (clickCount || 1); i += 1) {
        el.dispatchEvent(new MouseEvent("mousedown", init));
        el.dispatchEvent(new MouseEvent("mouseup", init));
        el.dispatchEvent(new MouseEvent("click", Object.assign({}, init, { detail: i + 1 })));
    }
    return { clicked: true, navigation: { started: false, same_document: null } };
}

function submitForm(formId, submitterNodeId) {
    console.log("[agent-utils] submitForm called with formId:", formId, "submitterNodeId:", submitterNodeId);
    const store = ensureFrameStore();
    const f = store.elFor(formId);
    if (!f || !(f instanceof HTMLFormElement)) {
        console.error("[agent-utils] submitForm: form not found:", formId);
        return { error: { code: "not_found", message: "Form not found or detached" } };
    }
    console.log("[agent-utils] submitForm: found form element", f);
    let prevented = false;
    const handler = (e) => {
        if (e.defaultPrevented) { prevented = true; }
    };
    f.addEventListener("submit", handler, { capture: true, once: true });
    try {
        if (submitterNodeId) {
            const btn = store.elFor(submitterNodeId);
            if (btn && typeof btn.click === "function") {
                btn.click();
            } else {
                f.requestSubmit ? f.requestSubmit() : f.submit();
            }
        } else {
            f.requestSubmit ? f.requestSubmit() : f.submit();
        }
    } catch (e) {
        return { error: { code: "exception", message: String(e && e.message || e) } };
    }
    const result = {
        submitted: true,
        prevented: prevented,
        navigation: { occurred: null, url: null, same_document: null },
        form_data_sent_preview: [] // Not exposed synchronously without intercepting submit
    };
    console.log("[agent-utils] submitForm: result:", result);
    return result;
}

function validateForm(formId) {
    const store = ensureFrameStore();
    const f = store.elFor(formId);
    if (!f || !(f instanceof HTMLFormElement)) {
        return { error: { code: "not_found", message: "Form not found or detached" } };
    }
    const fields = [];
    for (const el of Array.from(f.elements || [])) {
        if (!(el instanceof HTMLElement)) { continue; }
        if (!("validity" in el)) { continue; }
        const valid = el.validity.valid;
        const errors = [];
        const v = el.validity;
        if (!valid) {
            if (v.valueMissing) { errors.push("valueMissing"); }
            if (v.typeMismatch) { errors.push("typeMismatch"); }
            if (v.patternMismatch) { errors.push("patternMismatch"); }
            if (v.tooLong) { errors.push("tooLong"); }
            if (v.tooShort) { errors.push("tooShort"); }
            if (v.rangeUnderflow) { errors.push("rangeUnderflow"); }
            if (v.rangeOverflow) { errors.push("rangeOverflow"); }
            if (v.stepMismatch) { errors.push("stepMismatch"); }
            if (v.badInput) { errors.push("badInput"); }
            if (v.customError) { errors.push("customError"); }
        }
        fields.push({
            field_id: window.__iTermFormStore.idFor(el),
            valid: !!valid,
            errors: errors,
            validation_message: el.validationMessage || ""
        });
    }
    return { valid: f.checkValidity(), fields: fields };
}

function inferSemantics(formId, locale) {
    const store = ensureFrameStore();
    const f = store.elFor(formId);
    if (!f || !(f instanceof HTMLFormElement)) {
        return { error: { code: "not_found", message: "Form not found or detached" } };
    }
    const mapping = [];
    function score(field, role) {
        // Heuristics: autocomplete attribute > label text > name
        let s = 0;
        const ac = (field.getAttribute("autocomplete") || "").toLowerCase();
        if (ac.includes(role)) { s += 0.6; }
        const labs = labelsFor(field).join(" ").toLowerCase();
        if (labs.includes(role.replace("_", " "))) { s += 0.25; }
        const nm = (field.name || "").toLowerCase();
        if (nm.includes(role.replace("_", ""))) { s += 0.15; }
        return Math.min(0.99, s);
    }
    const roles = ["email", "password", "given_name", "family_name", "address_line1", "address_line2", "city", "region", "postal_code", "country", "phone", "cc_number", "cc_exp", "cc_cvc", "search_query", "otp"];
    for (const el of Array.from(f.elements || [])) {
        if (!(el instanceof HTMLElement)) { continue; }
        const k = controlKind(el);
        if (k === "hidden" || k === "checkbox" || k === "radio" || k === "file" || k === "unknown") { continue; }
        for (const role of roles) {
            const conf = score(el, role);
            if (conf >= 0.5) {
                mapping.push({ role: role, field_id: store.idFor(el), confidence: Number(conf.toFixed(2)) });
            }
        }
    }
    return { mapping: mapping };
}

function focusField(fieldId) {
    const store = ensureFrameStore();
    const el = store.elFor(fieldId);
    if (!el) { return { error: { code: "not_found", message: "Field not found or detached" } }; }
    try { el.focus(); } catch (_) {}
    return { focused: document.activeElement === el };
}

function blurField(fieldId) {
    const store = ensureFrameStore();
    const el = store.elFor(fieldId);
    if (!el) { return { error: { code: "not_found", message: "Field not found or detached" } }; }
    try { el.blur(); } catch (_) {}
    return { blurred: document.activeElement !== el };
}

function scrollIntoViewById(nodeId, align) {
    const store = ensureFrameStore();
    const el = store.elFor(nodeId);
    if (!el) { return { error: { code: "not_found", message: "Node not found or detached" } }; }
    try {
        el.scrollIntoView({ block: align || "nearest", inline: "nearest" });
        return { scrolled: true };
    } catch (e) {
        return { error: { code: "exception", message: String(e && e.message || e) } };
    }
}

function detectChallengeSnapshot(formIdNullable) {
    const store = ensureFrameStore();
    const roots = [document];
    const out = [];
    function push(kind, severity, node) {
        out.push({ kind, severity, node_id: node ? store.idFor(node) : null });
    }
    // reCAPTCHA/Turnstile/hCaptcha markers
    if (document.querySelector(".g-recaptcha, div[id^='g-recaptcha'], iframe[src*='google.com/recaptcha']")) {
        push("recaptcha", "hard", document.querySelector(".g-recaptcha") || document.querySelector("iframe[src*='recaptcha']"));
    }
    if (document.querySelector("iframe[src*='hcaptcha.com']")) {
        push("hcaptcha", "hard", document.querySelector("iframe[src*='hcaptcha.com']"));
    }
    if (document.querySelector("iframe[src*='challenges.cloudflare.com']")) {
        push("turnstile", "soft", document.querySelector("iframe[src*='challenges.cloudflare.com']"));
    }
    // OTP fields
    const otp = document.querySelector("input[autocomplete='one-time-code'], input[name*='otp' i]");
    if (otp) { push("otp", "soft", otp); }
    // WebAuthn (high-level hint via buttons)
    const webauthnBtn = Array.from(document.querySelectorAll("button")).find(b => /passkey|security key|webauthn/i.test(b.textContent || ""));
    if (webauthnBtn) { push("webauthn", "soft", webauthnBtn); }
    return { challenges: out };
}

function mapActionNodes(formIdNullable) {
    const store = ensureFrameStore();
    const scope = (() => {
        if (!formIdNullable) { return document; }
        const f = store.elFor(formIdNullable);
        return f && f instanceof HTMLFormElement ? f : document;
    })();
    const candidates = [];
    function add(node, action, label, confidence) {
        candidates.push({ node_id: store.idFor(node), action, label, confidence });
    }
    const btns = Array.from(scope.querySelectorAll("button, input[type='submit'], input[type='button']"));
    for (const b of btns) {
        const label = (b.textContent || b.value || "").trim();
        const l = label.toLowerCase();
        if (!label) { continue; }
        if (/continue|next|proceed/.test(l)) { add(b, "next", label, 0.8); continue; }
        if (/back|previous/.test(l)) { add(b, "back", label, 0.7); continue; }
        if (/submit|sign in|log in|sign up|register|create account/.test(l)) { add(b, "submit", label, 0.85); continue; }
        if (/google/.test(l)) { add(b, "oauth-google", label, 0.8); continue; }
        if (/apple/.test(l)) { add(b, "oauth-apple", label, 0.8); continue; }
    }
    return { candidates };
}

// Robust same-document route/change waiter.
// Resolves when: hashchange OR pushState/replaceState change URL OR popstate moves history OR
// (as a last resort) URL mutation detected via polling. Optional DOM-change heuristic included.
async function waitSameDocumentChange(timeoutMs) {
    console.log("[agent-utils] waitSameDocumentChange called with timeout:", timeoutMs, "current URL:", location.href);
    return new Promise((resolve) => {
        const startUrl = String(location.href);
        let done = false;
        console.log("[agent-utils] waitSameDocumentChange: starting to wait, startUrl:", startUrl);

        const finish = (kind) => {
            if (done) { return; }
            done = true;
            console.log("[agent-utils] waitSameDocumentChange: satisfied via", kind, "new URL:", location.href);
            cleanup();
            resolve({ satisfied: true, details: { kind, url: String(location.href) } });
        };

        const timeout = setTimeout(() => {
            if (!done) {
                done = true;
                console.log("[agent-utils] waitSameDocumentChange: timed out after", timeoutMs, "ms");
                cleanup();
                resolve({ satisfied: false });
            }
        }, Math.max(0, timeoutMs ?? 5000));

        // 1) hashchange
        const onHash = () => {
            if (location.href !== startUrl) { finish("hashchange"); }
        };
        window.addEventListener("hashchange", onHash);

        // 2) history.pushState / replaceState
        //   - pushState/replaceState do NOT fire popstate immediately.
        const origPush = history.pushState;
        const origReplace = history.replaceState;

        try {
            if (!history.__iTermPatched) {
                history.pushState = function patchedPushState(state, title, url) {
                    const r = origPush.apply(this, arguments);
                    // If URL argument is provided and changes the serialized URL → success.
                    if (typeof url !== "undefined") {
                        queueMicrotask(() => {
                            if (location.href !== startUrl) { finish("pushstate"); }
                        });
                    }
                    return r;
                };
                history.replaceState = function patchedReplaceState(state, title, url) {
                    const r = origReplace.apply(this, arguments);
                    if (typeof url !== "undefined") {
                        queueMicrotask(() => {
                            if (location.href !== startUrl) { finish("replacestate"); }
                        });
                    }
                    return r;
                };
                Object.defineProperty(history, "__iTermPatched", { value: true });
            }
        } catch (e) {
            console.error(e);
        }

        // 3) popstate (back/forward)
        const onPop = () => {
            if (location.href !== startUrl) { finish("popstate"); }
        };
        window.addEventListener("popstate", onPop);

        // 4) Polling backstop for URL changes even if no event fires (rare router edge cases)
        const poll = setInterval(() => {
            if (location.href !== startUrl) { finish("poll"); }
        }, 100);

        // 5) Optional DOM-change heuristic: if URL unchanged but page visibly mutates soon after submit
        // Use a lightweight MO on <body>; resolves only if URL actually changes (we keep this as a hint).
        // Commented out by default to avoid false positives; uncomment if you want heuristic success.
        // const mo = new MutationObserver(() => { /* left as hint; do not finish here */ });
        // mo.observe(document.body || document.documentElement, { childList: true, subtree: true, attributes: true });

        function cleanup() {
            clearTimeout(timeout);
            clearInterval(poll);
            window.removeEventListener("hashchange", onHash);
            window.removeEventListener("popstate", onPop);
            // Do not attempt to restore history methods; other code may rely on our patch.
        }
    });
}
