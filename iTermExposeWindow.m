//
//  iTermExposeWindow.m
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import "iTermExposeWindow.h"
#import "iTermExpose.h"

@implementation iTermExposeWindow

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)keyDown:(NSEvent*)event
{
    NSString *unmodkeystr = [event charactersIgnoringModifiers];
    unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    if (unmodunicode == 27) {
        [iTermExpose toggle];
    }
}

- (BOOL)disableFocusFollowsMouse
{
    return YES;
}

@end
