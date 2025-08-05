 (function() {
   function sizeValue(link) {
     var sz = link.getAttribute('sizes');
     if (sz === 'any') {
       return Number.MAX_SAFE_INTEGER;
     }
     if (!sz) {
       return 0;
     }
     var parts = sz.split('x').map(function(n) {
       return parseInt(n, 10) || 0;
     });
     return (parts[0] * parts[1]) || 0;
   }
   function getFavicons() {
     var links = document.querySelectorAll('link[rel]');
     var icons = [];

     Array.prototype.forEach.call(links, function(link) {
       if (!link.getAttribute('href')) return;
       var rels = link.getAttribute('rel').toLowerCase().split(/\s+/);
       if (rels.indexOf('icon') !== -1 || rels.indexOf('mask-icon') !== -1) {
         icons.push({
           href: new URL(link.getAttribute('href'), document.baseURI).href,
           media: link.getAttribute('media') || '',
           color: link.getAttribute('color') || '',
           isMask: rels.indexOf('mask-icon') !== -1,
           area: sizeValue(link)
         });
       }
     });

     if (icons.length === 0) {
       return [{
         href: new URL('/favicon.ico', location.origin).href,
         media: '',
         color: '',
         isMask: false,
         area: 0
       }];
     }

     return icons;
   }

   return getFavicons();
 })();
