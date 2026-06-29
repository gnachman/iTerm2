//
//  iTermSystemVersion.m
//  iTerm2
//
//  Created by George Nachman on 1/3/16.
//
//

#import "iTermSystemVersion.h"
#import <Cocoa/Cocoa.h>

BOOL IsTouchBarAvailable(void) {
    // Checking for OS version doesn't work because there were two different 10.12.1's.
    return [NSApp respondsToSelector:@selector(setAutomaticCustomizeTouchBarMenuItemEnabled:)];
}
