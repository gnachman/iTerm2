(function(skipChrome) {
    // Begin turndown
    {{INCLUDE:turndown.browser.umd.js}}
    // End turndown
    const service = new TurndownService({
        headingStyle: 'atx',
        codeBlockStyle: 'fenced'
    });

    service.addRule('removeMedia', {
        filter: [
            'img',
            'video',
            'audio',
            'picture',
            'source',
            'track',
            'embed',
            'object'
        ],
        replacement: () => ''
    });

    if (skipChrome) {
        service.addRule('skipChrome', {
            filter: node => ['NAV', 'FOOTER', 'ASIDE', 'HEADER'].includes(node.tagName),
            replacement: () => ''
        });
    }

    const clone = document.documentElement.cloneNode(true);
    clone
        .querySelectorAll('script, style')
        .forEach(e => e.remove());

    const bodyEl = clone.querySelector('body');

    let root;

    if (skipChrome) {
        root = clone.querySelector('main, article, [role="main"]')
            || bodyEl || clone;
    } else {
        root = bodyEl || clone;
    }
    const markdown = service.turndown(root.innerHTML);
    return markdown;
})({{SKIP_CHROME}});
