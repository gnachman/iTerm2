//
//  iTermBaseWKWebView.m
//  iTerm2
//
//  Created by George Nachman on 7/29/25.
//

#import "iTermBaseWKWebView.h"

@implementation iTermBaseWKWebView
- (void)insertText:(id)insertString replacementRange:(NSRange)replacementRange {
    [super insertText:insertString replacementRange:replacementRange];
}

- (void)doCommandBySelector:(SEL)selector {
    [super doCommandBySelector:selector];
}
@end
