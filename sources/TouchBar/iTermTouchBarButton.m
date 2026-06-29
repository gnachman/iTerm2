//
//  iTermTouchBarButton.m
//  iTerm2
//
//  Created by George Nachman on 11/23/16.
//
//

#import "iTermTouchBarButton.h"

@implementation iTermTouchBarButton

- (void)dealloc {
    [_keyBindingAction release];
    [super dealloc];
}

@end
