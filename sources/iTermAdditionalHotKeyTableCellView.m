//
//  iTermAdditionalHotKeyTableCellView.m
//  iTerm2
//
//  Created by George Nachman on 7/7/16.
//
//

#import "iTermAdditionalHotKeyTableCellView.h"

#import "iTermAdditionalHotKeyObjectValue.h"

@implementation iTermAdditionalHotKeyTableCellView {
    iTermAdditionalHotKeyObjectValue *_objectValue;
    IBOutlet iTermShortcutInputView *_shortcut;
    IBOutlet NSView *_duplicateWarning;
}

- (void)awakeFromNib {
    _shortcut.shortcutDelegate = self;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    [super setBackgroundStyle:backgroundStyle];
    _shortcut.backgroundStyle = backgroundStyle;
}
- (void)setObjectValue:(iTermAdditionalHotKeyObjectValue *)objectValue {
    [_objectValue autorelease];
    _objectValue = [objectValue retain];
    _shortcut.stringValue = objectValue.shortcut.stringValue;
    _duplicateWarning.hidden = objectValue ? !objectValue.isDuplicate : YES;
}

- (iTermAdditionalHotKeyObjectValue *)objectValue {
    return _objectValue;
}

#pragma mark - iTermShortcutInputViewDelegate

- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    [_objectValue.shortcut setFromEvent:event];
    _duplicateWarning.hidden = !_objectValue.isDuplicate;
}

@end

