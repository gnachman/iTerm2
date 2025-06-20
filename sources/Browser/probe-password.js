(function() {
    let el = document.activeElement;
    if (!el || el.tagName.toLowerCase() !== 'input') {
        return {found: false};
    }
    let style = window.getComputedStyle(el);
    let visible = style.display !== 'none'
               && style.visibility !== 'hidden'
               && el.offsetParent !== null;
    return {found: true,
            isPassword: el.type === 'password',
            visible: visible};
})()
