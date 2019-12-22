//
//  iTermClickableTextField.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/19.
//

#import "iTermClickableTextField.h"

@implementation iTermClickableTextField

- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:self.attributedStringValue];
    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithContainerSize:self.bounds.size];
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
    [layoutManager addTextContainer:textContainer];
    [textStorage addLayoutManager:layoutManager];

    NSInteger index = [layoutManager characterIndexForPoint:point inTextContainer:textContainer fractionOfDistanceBetweenInsertionPoints:nil];
    if (index >= 0 && index < self.attributedStringValue.length) {
        NSDictionary *attributes = [self.attributedStringValue attributesAtIndex:index effectiveRange:nil];
        NSURL *url = attributes[NSLinkAttributeName];
        if (url) {
            [self openURL:url];
            return;
        }
    }
    [super mouseUp:event];
}

- (void)openURL:(NSURL *)url {
    [[NSWorkspace sharedWorkspace] openURL:url];
}

@end

