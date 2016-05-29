//
//  iTermWebViewWrapperView.m
//  iTerm2
//
//  Created by George Nachman on 11/3/15.
//
//

#import "iTermWebViewWrapperViewController.h"
#import "iTermFlippedView.h"

@interface iTermWebViewWrapperViewController ()
@property(nonatomic, retain) FutureWKWebView *webView;
@end


@implementation iTermWebViewWrapperViewController

- (instancetype)initWithWebView:(FutureWKWebView *)webView {
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

@end

