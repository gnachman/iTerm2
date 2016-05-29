//
//  NSTextField+iTerm.h
//  iTerm
//
//  Created by George Nachman on 1/27/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSTextField (iTerm)

- (BOOL)textFieldIsFirstResponder;
- (void)setLabelEnabled:(BOOL)enabled;

// For fields with stringValue's like 1,234, returns an int like 1234.
// Annoyingly, [field setIntValue:1234] places a stringValue of "1,234"
// in field, which [field intValue] parses as "1", so use this instead.
- (int)separatorTolerantIntValue;
- (NSUInteger)separatorTolerantUnsignedIntegerValue;

// Remove this text field from the view hierarchy and replace it with an identical one that is a
// clickable hyperlink. This works around a bug where changing a text field's attributed string to
// have an underline shifts it down by one point in OS 10.11 (and maybe other versions, I didn't
// check).
- (NSTextField *)replaceWithHyperlinkTo:(NSURL *)url;

@end
