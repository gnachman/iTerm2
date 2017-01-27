//
//  ToolWebView.m
//  iTerm2
//
//  Created by George Nachman on 11/9/16.
//
//

#import "ToolWebView.h"
#import "FutureMethods.h"

@implementation ToolWebView {
    FutureWKWebView *_webView;
}

- (instancetype)initWithFrame:(NSRect)frame URL:(NSURL *)url {
    self = [super initWithFrame:frame];
    if (self) {
        FutureWKWebViewConfiguration *configuration = [[[FutureWKWebViewConfiguration alloc] init] autorelease];
        if (!configuration) {
            return nil;
        }
        if (configuration) {
            // If you get here, it's OS 10.10 or newer.
            configuration.applicationNameForUserAgent = @"iTerm2";
            FutureWKPreferences *prefs = [[[FutureWKPreferences alloc] init] autorelease];
            prefs.javaEnabled = NO;
            prefs.javaScriptEnabled = YES;
            prefs.javaScriptCanOpenWindowsAutomatically = NO;
            configuration.preferences = prefs;
            configuration.processPool = [[[FutureWKProcessPool alloc] init] autorelease];
            FutureWKUserContentController *userContentController =
                [[[FutureWKUserContentController alloc] init] autorelease];
            configuration.userContentController = userContentController;
            configuration.websiteDataStore = [FutureWKWebsiteDataStore defaultDataStore];
            FutureWKWebView *webView = [[[FutureWKWebView alloc] initWithFrame:self.bounds
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
