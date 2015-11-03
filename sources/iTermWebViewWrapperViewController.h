//
//  iTermWebViewWrapperView.h
//  iTerm2
//
//  Created by George Nachman on 11/3/15.
//
//

#import <Cocoa/Cocoa.h>
#import "FutureMethods.h"

@interface iTermWebViewWrapperViewController : NSViewController

- (instancetype)initWithWebView:(FutureWKWebView *)webView;

@end
