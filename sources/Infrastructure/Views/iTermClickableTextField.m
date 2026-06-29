//
//  iTermClickableTextField.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/19.
//

#import "iTermClickableTextField.h"
#import "NSWorkspace+iTerm.h"

@implementation iTermClickableTextField

// Deliver the click that activates a background window to this field too, so a
// link fires on the first click instead of being swallowed by app activation.
// Without this, clicking a link while another app is active does nothing (the
// click only activates iTerm2); the user has to click a second time. This field
// is non-editable display text, so accepting the first mouse can't disturb an
// insertion point or selection.
- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:self.attributedStringValue];
    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithContainerSize:self.bounds.size];
    // Match how NSTextFieldCell lays out the text so the hit-tested character is
    // the one actually drawn under the click. A freshly-created NSTextContainer
    // defaults to lineFragmentPadding 5, but the cell draws with 2; the wider
    // padding makes our layout wrap earlier than what's on screen, so for
    // multi-line wrapped text a click lands several characters before the
    // intended one (e.g. just short of a trailing link). Also mirror the field's
    // wrapping mode and line limit so line breaks line up exactly.
    textContainer.lineFragmentPadding = 2;
    textContainer.maximumNumberOfLines = self.maximumNumberOfLines;
    textContainer.lineBreakMode = self.lineBreakMode;
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
    [[NSWorkspace sharedWorkspace] it_openURL:url
                                       target:nil
                                        style:iTermOpenStyleTab
                                       window:self.window];
}

@end

