//
//  iTermWebViewWrapperView.m
//  iTerm2
//
//  Created by George Nachman on 11/3/15.
//
//

#import "iTermWebViewWrapperViewController.h"

#import "DebugLogging.h"
#import "iTermFlippedView.h"
#import "iTermScriptFunctionCall.h"
#import "iTermSystemVersion.h"
#import "iTermVariableScope.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import <WebKit/WebKit.h>

static char iTermWebViewFactoryUserControllerDelegateKey;
static char iTermWebViewFactoryUserControllerWebviewKey;
NSString *const iTermWebViewErrorDomain = @"com.iterm2.webview";

@interface iTermWebViewWrapperViewController ()
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, copy) NSURL *backupURL;
@end

@interface WKPreferences(Private)
- (void)_setWebSecurityEnabled:(BOOL)enabled;
@end

@implementation iTermWebViewWrapperViewController

- (instancetype)initWithWebView:(WKWebView *)webView backupURL:(NSURL *)backupURL {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.webView = webView;
        self.backupURL = backupURL;
    }
    return self;
}

- (void)loadView {
    self.view = [[iTermFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    self.view.autoresizesSubviews = YES;

    CGFloat y;
    if (_backupURL != nil) {
        NSButton *button = [[NSButton alloc] init];
        [button setButtonType:NSMomentaryPushInButton];
        [button setTarget:self];
        [button setAction:@selector(openInBrowserButtonPressed:)];
        [button setTitle:[NSString stringWithFormat:@"Open in %@", [self browserName]]];
        [button setBezelStyle:NSTexturedRoundedBezelStyle];
        [button sizeToFit];
        NSRect frame = button.frame;
        frame.origin.x = self.view.frame.origin.x + 8;
        frame.origin.y = 8;
        button.frame = frame;
        button.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
        [self.view addSubview:button];
        y = NSMaxY(frame) + 8;
    } else {
        y = 0;
    }

    const NSRect frame = NSMakeRect(0, y, self.view.frame.size.width, self.view.frame.size.height - y);
    self.webView.frame = frame;
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:self.webView];
}

- (void)openInBrowserButtonPressed:(id)sender {
    NSURL *URL = self.webView.URL ?: self.backupURL;
    if ([URL isEqual:[NSURL URLWithString:@"about:blank"]]) {
        URL = self.backupURL;
    }
    [[NSWorkspace sharedWorkspace] openURL:URL];
}

- (NSString *)browserName {
    CFErrorRef error;
    NSURL *URL = self.webView.URL ?: [NSURL URLWithString:@"http://example.com"];
    NSURL *appUrl = (__bridge_transfer NSURL *)LSCopyDefaultApplicationURLForURL((__bridge CFURLRef)URL,
                                                                                 kLSRolesAll,
                                                                                 &error);
    if (appUrl) {
        NSString *name = nil;
        [appUrl getResourceValue:&name forKey:NSURLLocalizedNameKey error:NULL];
        if (name) {
            return name;
        }
    }
    return @"Default Browser";
}

- (void)terminateWebView {
    [_webView stopLoading];
    [_webView loadHTMLString:@"<html/>" baseURL:nil];
}

@end

@interface iTermWebViewFactory()<WKScriptMessageHandler, WKUIDelegate>
@end

@implementation iTermWebViewFactory

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (NSClassFromString(@"WKWebViewConfiguration")) {
            // If you get here, it's OS 10.10 or newer.
            instance = [[self alloc] init];
        }
    });
    return instance;
}

- (WKWebView *)webViewWithDelegate:(id<iTermWebViewDelegate>)delegate {
    Class WKWebViewClass = NSClassFromString(@"WKWebView");
    Class WKWebViewConfigurationClass = NSClassFromString(@"WKWebViewConfiguration");
    WKWebViewConfiguration *configuration = [[WKWebViewConfigurationClass alloc] init];

    configuration.applicationNameForUserAgent = @"iTerm2";

    WKPreferences *prefs = [[NSClassFromString(@"WKPreferences") alloc] init];
    prefs.javaEnabled = NO;
    prefs.javaScriptEnabled = YES;
    prefs.javaScriptCanOpenWindowsAutomatically = NO;
    if (@available(macOS 10.13, *)) {
        [prefs _setWebSecurityEnabled:NO];
    };
    @try {
        // oh ffs, you have to do this to get the web inspector to show up
        [prefs setValue:@YES forKey:@"developerExtrasEnabled"];
    } @catch (NSException *exception) {
        DLog(@"When setting developerExtrasEnabled: %@", exception);
    }

    configuration.preferences = prefs;
    configuration.processPool = [[NSClassFromString(@"WKProcessPool") alloc] init];

    [self registerUserScriptInConfiguration:configuration delegate:delegate];
    configuration.websiteDataStore = [NSClassFromString(@"WKWebsiteDataStore") defaultDataStore];
    WKWebView *webView = [[WKWebViewClass alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)
                                                 configuration:configuration];
    [configuration.userContentController it_setWeakAssociatedObject:webView forKey:&iTermWebViewFactoryUserControllerWebviewKey];
    webView.UIDelegate = self;

    return webView;
}

- (void)registerUserScriptInConfiguration:(WKWebViewConfiguration *)configuration delegate:(id<iTermWebViewDelegate>)delegate {
    WKUserContentController *userController = [[WKUserContentController alloc] init];
    [userController it_setWeakAssociatedObject:delegate forKey:&iTermWebViewFactoryUserControllerDelegateKey];
    [userController addScriptMessageHandler:self name:@"iterm2Invoke"];

    NSURL *url = [[NSBundle bundleForClass:[self class]] URLForResource:@"iterm2Invoke" withExtension:@"js"];
    NSString *js = [NSString stringWithContentsOfURL:url
                                            encoding:NSUTF8StringEncoding
                                               error:NULL];
    if (!js) {
        DLog(@"Failed to get iterm2Invoke.js");
        return;
    }

    // Specify when and where and what user script needs to be injected into the web document
    WKUserScript *userScript = [[WKUserScript alloc] initWithSource:js
                                                      injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                   forMainFrameOnly:NO];
    [userController addUserScript:userScript];
    configuration.userContentController = userController;
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"iterm2Invoke"]) {
        NSDictionary *dict = [NSDictionary castFrom:message.body];
        NSString *invocation = dict[@"invocation"];
        WKWebView *webview = [userContentController it_associatedObjectForKey:&iTermWebViewFactoryUserControllerWebviewKey];
        if (!webview) {
            assert(NO);
            return;
        }

        __weak id<iTermWebViewDelegate> delegate = [userContentController it_associatedObjectForKey:&iTermWebViewFactoryUserControllerDelegateKey];
        if (!invocation) {
            [self sendReturnValue:nil forMessage:dict toWebview:webview completion:nil];
            [delegate itermWebViewScriptInvocation:nil
                                  didFailWithError:[NSError errorWithDomain:iTermWebViewErrorDomain
                                                                       code:iTermWebViewErrorCodeMissingInvocation
                                                                   userInfo:nil]];
            return;
        }
        iTermVariableScope *scope = [delegate itermWebViewScriptScopeForUserContentController:userContentController];
        if (!scope) {
            NSError *error = [NSError errorWithDomain:iTermWebViewErrorDomain
                                                 code:iTermWebViewErrorCodeReceiverDealloced
                                             userInfo:nil];
            [self sendReturnValue:error forMessage:dict toWebview:webview completion:nil];
            return;
        }
        [iTermScriptFunctionCall callFunction:invocation
                                      timeout:[[NSDate distantFuture] timeIntervalSinceNow]
                                        scope:scope
                                   retainSelf:YES
                                   completion:^(id value, NSError *error, NSSet<NSString *> *missing) {
                                       if (error) {
                                           [delegate itermWebViewScriptInvocation:invocation
                                                                 didFailWithError:error];
                                           return;
                                       }
                                       [self sendReturnValue:value forMessage:dict toWebview:webview completion:^(NSError *innerError) {
                                           if (!innerError) {
                                               return;
                                           }
                                           [delegate itermWebViewScriptInvocation:invocation
                                                                 didFailWithError:innerError];

                                       }];
                                   }];
    }
}

- (void)sendReturnValue:(id)value
             forMessage:(NSDictionary *)message
              toWebview:(WKWebView *)webview
             completion:(void (^)(NSError *))completion {
    NSString *callback = message[@"callback"];
    if (!callback) {
        if (completion) {
            completion([NSError errorWithDomain:iTermWebViewErrorDomain code:iTermWebViewErrorCodeMissingCallback userInfo:nil]);
        }
        return;
    }
    NSString *innerScript = nil;
    NSString *script = nil;
    NSError *error = [NSError castFrom:value];
    if (error) {
        script = innerScript = [NSString stringWithFormat:@"throw %@", [NSJSONSerialization it_jsonStringForObject:error.localizedDescription]];
    } else {
        innerScript = [NSString stringWithFormat:@"%@(%@)", callback, [NSJSONSerialization it_jsonStringForObject:value]];
        script = [NSString stringWithFormat:@"try { %@; } catch(err) { alert('Caught error while sending return value to javascript: ' + err.message + '\\n' + err.stack); }", innerScript];
    }
    __weak id<iTermWebViewDelegate> delegate = [webview.configuration.userContentController it_associatedObjectForKey:&iTermWebViewFactoryUserControllerDelegateKey];
    [delegate itermWebViewWillExecuteJavascript:innerScript];
    [webview evaluateJavaScript:script completionHandler:^(id _Nullable value, NSError * _Nullable error) {
        if (!error) {
            return;
        }
        if (!completion) {
            return;
        }
        NSString *description;
        NSString *messageKey = @"WKJavaScriptExceptionMessage";
        NSString *lineKey = @"WKJavaScriptExceptionLineNumber";
        if (error.userInfo[messageKey]) {
            description = [NSString stringWithFormat:@"Error evaluating '%@' at line %@: %@", innerScript, error.userInfo[lineKey], error.userInfo[messageKey]];
        }
        completion([NSError errorWithDomain:iTermWebViewErrorDomain
                                       code:iTermWebViewErrorCodeRPCFailed
                                   userInfo:@{ NSLocalizedDescriptionKey: description ?: @"Unknown error" }]);
    }];
}

#pragma mark - WKUIDelegate

- (void)webView:(WKWebView *)webView
runJavaScriptAlertPanelWithMessage:(NSString *)message
initiatedByFrame:(WKFrameInfo *)frame
completionHandler:(void (^)(void))completionHandler {
    __weak id<iTermWebViewDelegate> delegate = [webView.configuration.userContentController it_associatedObjectForKey:&iTermWebViewFactoryUserControllerDelegateKey];
    [delegate itermWebViewJavascriptError:message];
    completionHandler();
}

@end
