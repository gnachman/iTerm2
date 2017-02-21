//
//  ToolWebView.m
//  iTerm2
//
//  Created by George Nachman on 11/9/16.
//
//

#import "ToolWebView.h"
#import "FutureMethods.h"
#import "iTermSystemVersion.h"

#import <WebKit/WebKit.h>

@implementation ToolWebView {
    WKWebView *_webView;
}

- (instancetype)initWithFrame:(NSRect)frame URL:(NSURL *)url {
    self = [super initWithFrame:frame];
    if (self) {
        WKWebViewConfiguration *configuration = [[[WKWebViewConfiguration alloc] init] autorelease];
        if (!configuration) {
            return nil;
        }
        if (configuration) {
            // If you get here, it's OS 10.10 or newer.
            ITERM_IGNORE_PARTIAL_BEGIN
            if (IsElCapitanOrLater()) {
                configuration.applicationNameForUserAgent = @"iTerm2";
            }
            ITERM_IGNORE_PARTIAL_END
            WKPreferences *prefs = [[[WKPreferences alloc] init] autorelease];
            prefs.javaEnabled = NO;
            prefs.javaScriptEnabled = YES;
            prefs.javaScriptCanOpenWindowsAutomatically = NO;
            configuration.preferences = prefs;
            configuration.processPool = [[[WKProcessPool alloc] init] autorelease];
            WKUserContentController *userContentController =
                [[[WKUserContentController alloc] init] autorelease];
            configuration.userContentController = userContentController;
            ITERM_IGNORE_PARTIAL_BEGIN
            if (IsElCapitanOrLater()) {
                configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
            }
            ITERM_IGNORE_PARTIAL_END
            WKWebView *webView = [[[WKWebView alloc] initWithFrame:self.bounds
                                                                 configuration:configuration] autorelease];
            NSURLRequest *request = [[[NSURLRequest alloc] initWithURL:url] autorelease];
            [webView loadRequest:request];
            [self addSubview:webView];
            _webView = [webView retain];
        }
    }
    return self;
}

- (void)dealloc {
    [_webView release];
    [super dealloc];
}

- (CGFloat)minimumHeight {
    return 15;
}

- (void)relayout {
    _webView.frame = self.bounds;
}

@end
