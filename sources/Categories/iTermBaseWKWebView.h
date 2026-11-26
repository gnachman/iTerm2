//
//  iTermBaseWKWebView.h
//  iTerm2
//
//  Created by George Nachman on 7/29/25.
//

#import <WebKit/WebKit.h>

// WKWebView implements these privately. Declaring them lets the Swift class
// iTermBaseWKWebView override them and its subclass call super. This header
// is imported by the bridging header.
@interface WKWebView(iTerm)
- (void)insertText:(id)insertString replacementRange:(NSRange)replacementRange;
- (void)doCommandBySelector:(SEL)selector;
@end
