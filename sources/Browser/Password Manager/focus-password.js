 (function() {
     const requirePassword = true;
     const prefocus = {{ID}};

     const el = document.getElementById(prefocus);
     if (el instanceof HTMLElement && typeof el.focus === 'function') {
         el.focus();
         return true;
     } else {
         return false;
     }
 })();
