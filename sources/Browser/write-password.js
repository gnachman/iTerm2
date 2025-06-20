(function() {
    const pw = {{PASSWORD}};
    const requirePassword = {{REQUIRE_SECURE}};

    let el = document.activeElement;
    if (!el || el.tagName.toLowerCase() !== 'input') {
        return false;
    }

    // only allow password inputs when required
    if (requirePassword && el.type.toLowerCase() !== 'password') {
        return false;
    }

    // disallow disabled or readonly
    if (el.disabled || el.readOnly) {
        return false;
    }

    // disallow hidden/offscreen
    const style = window.getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden' || el.offsetParent === null) {
        return false;
    }

    el.focus();
    el.value = pw;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
})();
