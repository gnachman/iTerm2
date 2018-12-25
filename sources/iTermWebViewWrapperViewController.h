//
//  iTermWebViewWrapperView.h
//  iTerm2
//
//  Created by George Nachman on 11/3/15.
//
//

#import <Cocoa/Cocoa.h>

@class iTermVariableScope;
@class WKUserContentController;
@class WKWebView;

extern NSString *const iTermWebViewErrorDomain;
typedef NS_ENUM(NSUInteger, iTermWebViewErrorCode) {
    iTermWebViewErrorCodeMissingInvocation,
    iTermWebViewErrorCodeReceiverDealloced,
    iTermWebViewErrorCodeRPCFailed,
    iTermWebViewErrorCodeMissingCallback,
    iTermWebViewErrorCodeCallbackFailed
};

@protocol iTermWebViewDelegate<NSObject>
- (void)itermWebViewScriptInvocation:(NSString *)invocation
                    didFailWithError:(NSError *)error;
- (iTermVariableScope *)itermWebViewScriptScopeForUserContentController:(WKUserContentController *)userContentController;
- (void)itermWebViewJavascriptError:(NSString *)errorText;
- (void)itermWebViewWillExecuteJavascript:(NSString *)javascript;
@end

@interface iTermWebViewWrapperViewController : NSViewController

- (instancetype)initWithWebView:(WKWebView *)webView backupURL:(NSURL *)backupURL;

- (void)terminateWebView;

@end

@interface iTermWebViewFactory : NSObject
+ (instancetype)sharedInstance;
- (WKWebView *)webViewWithDelegate:(id<iTermWebViewDelegate>)delegate;
@end
