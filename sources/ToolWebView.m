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
#import "iTermToolbeltView.h"
#import "NSObject+iTerm.h"

#import <WebKit/WebKit.h>

@implementation ToolWebView {
    WKWebView *_webView;
    NSURL *_url;
    NSString *_identifier;
}

- (instancetype)initWithFrame:(NSRect)frame URL:(NSURL *)url identifier:(NSString *)identifier {
    self = [super initWithFrame:frame];
    if (self) {
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
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
            WKPreferences *prefs = [[WKPreferences alloc] init];
            prefs.javaEnabled = NO;
            prefs.javaScriptEnabled = YES;
            prefs.javaScriptCanOpenWindowsAutomatically = NO;
            configuration.preferences = prefs;
            configuration.processPool = [[WKProcessPool alloc] init];
            WKUserContentController *userContentController =
                [[WKUserContentController alloc] init];
            configuration.userContentController = userContentController;
            ITERM_IGNORE_PARTIAL_BEGIN
            if (IsElCapitanOrLater()) {
                configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
            }
            ITERM_IGNORE_PARTIAL_END
            WKWebView *webView = [[WKWebView alloc] initWithFrame:self.bounds
                                                    configuration:configuration];
            [self addSubview:webView];
            _webView = webView;

            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(didRegister:)
                                                         name:iTermToolbeltDidRegisterDynamicToolNotification
                                                       object:nil];

            _url = [url copy];
            _identifier = [identifier copy];
            [self loadURL];
        }
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadURL {
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:_url];
    [_webView loadRequest:request];
}

- (CGFloat)minimumHeight {
    return 15;
}

- (void)relayout {
    _webView.frame = self.bounds;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    _webView.frame = self.bounds;
}

- (void)didRegister:(NSNotification *)notification {
    if ([NSObject object:notification.object isEqualToObject:_identifier]) {
        [self loadURL];
    }
}
@end
