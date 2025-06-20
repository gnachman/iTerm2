(function() {
  function getFaviconUrl() {
    var links = document.querySelectorAll('link[rel]');
    var icons = [];

    Array.prototype.forEach.call(links, function(link) {
      var rels = link.getAttribute('rel').toLowerCase().split(/\\s+/);

      if (rels.indexOf('icon') !== -1 || rels.indexOf('mask-icon') !== -1) {
        icons.push(link);
      }
    });

    if (icons.length) {
      icons.sort(function(a, b) {
        return sizeValue(b) - sizeValue(a);
      });

      return new URL(icons[0].getAttribute('href'), document.baseURI).href;
    }

    return new URL('/favicon.ico', location.origin).href;
  }

  function sizeValue(link) {
    var sz = link.getAttribute('sizes');
    if (!sz) {
      return 0;
    }

    var parts = sz.split('x').map(function(n) {
      return parseInt(n, 10) || 0;
    });

    return (parts[0] * parts[1]) || 0;
  }

  return getFaviconUrl();
})();
