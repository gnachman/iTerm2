//
//  ToolWebView.m
//  iTerm2
//
//  Created by George Nachman on 11/9/16.
//
//

#import "ToolWebView.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermSystemVersion.h"
#import "iTermToolbeltView.h"
#import "NSObject+iTerm.h"

#import <WebKit/WebKit.h>

static NSString *const iTermToolWebViewLogger = @"logger";

// WKUserContentController strongly retains its script message handler so it must be a separate
// object to avoid a cyclic dependency :(
@interface iTermLoggingScriptMessageHandler: NSObject<WKScriptMessageHandler>
@property (nonatomic, copy) NSString *identifier;
@end

@implementation iTermLoggingScriptMessageHandler
- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:iTermToolWebViewLogger]) {
        XLog(@"console.log for %@: %@", self.identifier, message.body);
    }
}

@end

@implementation ToolWebView {
    WKWebView *_webView;
    NSURL *_url;
    NSString *_identifier;
    iTermLoggingScriptMessageHandler *_messageHandler;
    WKUserContentController *_contentController;
}

- (instancetype)initWithFrame:(NSRect)frame URL:(NSURL *)url identifier:(NSString *)identifier {
    self = [super initWithFrame:frame];
    if (self) {
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        if (!configuration) {
            return nil;
        }
        if (configuration) {
            configuration.applicationNameForUserAgent = @"iTerm2";
            WKPreferences *prefs = [[WKPreferences alloc] init];
            prefs.javaScriptEnabled = YES;
            prefs.javaScriptCanOpenWindowsAutomatically = NO;
            configuration.preferences = prefs;
            configuration.processPool = [[WKProcessPool alloc] init];
            WKUserContentController *userContentController =
                [[WKUserContentController alloc] init];
            configuration.userContentController = userContentController;
            configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

            @try {
                [prefs setValue:@YES forKey:@"developerExtrasEnabled"];
            } @catch (NSException *exception) {
                DLog(@"When setting developerExtrasEnabled: %@", exception);
            }

            WKWebView *webView = [[WKWebView alloc] initWithFrame:self.bounds
                                                    configuration:configuration];

            NSString *js =
            @"(function() {"
            "  const oldLog = console.log;"
            "  console.log = function(...args) {"
            "    window.webkit.messageHandlers.logger.postMessage(args.map(String).join(' '));"
            "    oldLog.apply(console, args);"
            "  };"
            "})();"
            "window.onerror = function(message, source, lineno, colno, error) {"
            "    const payload = {"
            "        message: String(message),"
            "        source: String(source),"
            "        lineno: lineno,"
            "        colno: colno,"
            "        stack: error && error.stack ? String(error.stack) : null"
            "    };"
            "    window.webkit.messageHandlers.logger.postMessage(payload);"
            "};";

            WKUserContentController *controller = configuration.userContentController;
            _messageHandler = [[iTermLoggingScriptMessageHandler alloc] init];
            _messageHandler.identifier = [self description];
            _contentController = controller;
            [controller addScriptMessageHandler:_messageHandler name:iTermToolWebViewLogger];
            [controller addUserScript:[[WKUserScript alloc] initWithSource:js
                                                           injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                        forMainFrameOnly:NO]];

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
    [_contentController removeScriptMessageHandlerForName:iTermToolWebViewLogger];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadURL {
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:_url];
    DLog(@"%@: load %@", self, _url);
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
