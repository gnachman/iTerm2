(function() {
    const s = {{STRING}};
    const requirePassword = {{REQUIRE_SECURE}};
    const focusNextPw = {{FOCUS_NEXT_PW}};

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
    el.value = s;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));

    (function injectHighlightStyle() {
      if (document.getElementById('iterm2-password-highlight-style')) return;
      const style = document.createElement('style');
      style.id = 'iterm2-password-highlight-style';
      style.textContent = `
        @keyframes passwordFocusHighlight {
          0%   { box-shadow: 0 0 0px rgba(255, 165, 0, 0.0); }
          50%  { box-shadow: 0 0 8px rgba(255, 165, 0, 1.0); }
          100% { box-shadow: 0 0 0px rgba(255, 165, 0, 0.0); }
        }
        .password-highlight {
          animation: passwordFocusHighlight 1s ease-in-out;
        }
      `;
      document.head.appendChild(style);
    })();

    focusNextPasswordField = function() {
        const current = document.activeElement;
        if (!(current instanceof HTMLElement)) {
            return;
        }

        const currentRect = current.getBoundingClientRect();

        // collect all visible, enabled password inputs
        const passwords = Array.from(
            document.querySelectorAll('input[type="password"]:not([disabled])')
        ).filter(el => el.offsetParent !== null);

        let closest = null;
        let minDistance = Infinity;

        for (const el of passwords) {
            const r = el.getBoundingClientRect();
            // only consider those positioned below the current element
            if (r.top > currentRect.bottom) {
                const distance = r.top - currentRect.bottom;
                if (distance < minDistance) {
                    minDistance = distance;
                    closest = el;
                }
            }
        }

        if (closest) {
            closest.focus();
            closest.classList.add('password-highlight');
            closest.addEventListener('animationend', function _onAnim() {
                closest.classList.remove('password-highlight');
                closest.removeEventListener('animationend', _onAnim);
            });
        }
    }

    if (focusNextPw) {
        focusNextPasswordField();
    }
    return true;
})();
