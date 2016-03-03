//
//  iTermNativeWebViewController.m
//  iTerm2
//
//  Created by George Nachman on 3/2/16.
//
//

#import "iTermNativeWebViewController.h"
#import <WebKit/WebKit.h>

@interface iTermNativeWebViewController()<WKNavigationDelegate>
@end

@implementation iTermNativeWebViewController {
  WKWebView *_webView;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
  WKWebViewConfiguration *configuration = [[[WKWebViewConfiguration alloc] init] autorelease];
  if (!configuration) {
    return nil;
  }

  NSURL *url = [NSURL URLWithString:dictionary[@"url"]];
  if (!url) {
    return nil;
  }

  self = [super init];
  if (self) {
    // If you get here, it's OS 10.10 or newer.
    configuration.applicationNameForUserAgent = @"iTerm2";
    WKPreferences *prefs = [[[WKPreferences alloc] init] autorelease];
    prefs.javaEnabled = NO;
    prefs.javaScriptEnabled = YES;
    prefs.javaScriptCanOpenWindowsAutomatically = NO;
    configuration.preferences = prefs;
    configuration.processPool = [[WKProcessPool alloc] init];
    WKUserContentController *userContentController =
    [[[WKUserContentController alloc] init] autorelease];
    configuration.userContentController = userContentController;
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)
                                            configuration:configuration];

    NSURLRequest *request =
    [[[NSURLRequest alloc] initWithURL:url] autorelease];
    [webView loadRequest:request];
    _webView = webView;
    _webView.navigationDelegate = self;

    [self notifyViewReadyForDisplay];
  }
  return self;
}

- (void)dealloc {
  [_webView release];
  [super dealloc];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(null_unspecified WKNavigation *)navigation {
  [self notifyViewReadyForDisplay];
}

- (void)loadView {
  self.view = _webView;
}

@end
