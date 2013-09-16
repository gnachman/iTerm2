//
//  PTYToolbar.m
//  iTerm
//
//  Created by George Nachman on 3/18/13.
//
//

#import "PTYToolbar.h"
#import "FutureMethods.h"

@implementation PTYToolbar

- (void)setVisible:(BOOL)shown
{
    BOOL wasShown = [self isVisible];
    [super setVisible:shown];
    if (shown != wasShown) {
        id<PTYToolbarDelegate> delegate = (id<PTYToolbarDelegate>)[self delegate];
        if ([delegate respondsToSelector:@selector(toolbarDidChangeVisibility:)]) {
            [delegate_ toolbarDidChangeVisibility:self];
        }
    }
}

@end
