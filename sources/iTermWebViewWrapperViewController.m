//
//  iTermWebViewWrapperView.m
//  iTerm2
//
//  Created by George Nachman on 11/3/15.
//
//

#import "iTermWebViewWrapperViewController.h"
#import "iTermFlippedView.h"
#import <WebKit/WebKit.h>

@interface iTermWebViewWrapperViewController ()
@property(nonatomic, retain) WKWebView *webView;
@end


@implementation iTermWebViewWrapperViewController

- (instancetype)initWithWebView:(WKWebView *)webView {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    self.webView = webView;
  }
  return self;
}

- (void)loadView {
  self.view = [[[iTermFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)] autorelease];
  self.view.autoresizesSubviews = YES;

  NSButton *button = [[[NSButton alloc] init] autorelease];
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

  CGFloat y = NSMaxY(frame) + 8;
  frame = NSMakeRect(0, y, self.view.frame.size.width, self.view.frame.size.height - y);
  self.webView.frame = frame;
  self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [self.view addSubview:self.webView];
}

- (void)openInBrowserButtonPressed:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:self.webView.URL];
}

- (NSString *)browserName {
    CFErrorRef error;
    NSURL *URL = self.webView.URL ?: [NSURL URLWithString:@"http://example.com"];
    NSURL *appUrl = (NSURL *)LSCopyDefaultApplicationURLForURL((CFURLRef)URL,
                                                               kLSRolesAll,
                                                               &error);
    [appUrl autorelease];
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
    [[iTermWebViewPool sharedInstance] returnWebViewToPool:self.webView];
}

@end

@implementation iTermWebViewPool {
    NSMutableArray<WKWebView *> *_pool;
}

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

- (instancetype)init {
    self = [super init];
    if (self) {
        _pool = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_pool release];
    [super dealloc];
}

- (WKWebView *)webView {
    WKWebView *webView = [[_pool.firstObject retain] autorelease];
    if (webView) {
        [_pool removeObjectAtIndex:0];
         return webView;
    } else {
        Class WKWebViewClass = NSClassFromString(@"WKWebView");
        Class WKWebViewConfigurationClass = NSClassFromString(@"WKWebViewConfiguration");
        WKWebViewConfiguration *configuration = [[[WKWebViewConfigurationClass alloc] init] autorelease];

        configuration.applicationNameForUserAgent = @"iTerm2";
        WKPreferences *prefs = [[[NSClassFromString(@"WKPreferences") alloc] init] autorelease];
        prefs.javaEnabled = NO;
        prefs.javaScriptEnabled = YES;
        prefs.javaScriptCanOpenWindowsAutomatically = NO;
        configuration.preferences = prefs;
        configuration.processPool = [[[NSClassFromString(@"WKProcessPool") alloc] init] autorelease];
        WKUserContentController *userContentController =
            [[[NSClassFromString(@"WKUserContentController") alloc] init] autorelease];
        configuration.userContentController = userContentController;
        configuration.websiteDataStore = [NSClassFromString(@"WKWebsiteDataStore") defaultDataStore];
        WKWebView *webView = [[[WKWebViewClass alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)
                                                       configuration:configuration] autorelease];

        return webView;
    }
}

- (void)returnWebViewToPool:(WKWebView *)webView {
    [webView stopLoading];
    [webView loadHTMLString:@"<html/>" baseURL:nil];
    [_pool addObject:webView];
}

@end
