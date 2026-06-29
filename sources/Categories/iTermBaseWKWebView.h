//
//  iTermBaseWKWebView.h
//  iTerm2
//
//  Created by George Nachman on 7/29/25.
//

#import <WebKit/WebKit.h>

@interface WKWebView(iTerm)
- (void)insertText:(id)insertString replacementRange:(NSRange)replacementRange;
- (void)doCommandBySelector:(SEL)selector;
@end

@interface iTermBaseWKWebView: WKWebView
- (void)insertText:(id)insertString replacementRange:(NSRange)replacementRange;
- (void)doCommandBySelector:(SEL)selector;
@end
