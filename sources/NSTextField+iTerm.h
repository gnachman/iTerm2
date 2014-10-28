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

@end
