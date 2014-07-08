//
//  iTermAlphaColorWell.m
//  iTerm
//
//  Created by George Nachman on 7/7/14.
//
//

#import "iTermAlphaColorWell.h"

@implementation iTermAlphaColorWell

- (void)deactivate {
    [super deactivate];
    [[NSColorPanel sharedColorPanel] setShowsAlpha:NO];
}

- (void)activate:(BOOL)exclusive {
    [[NSColorPanel sharedColorPanel] setShowsAlpha:YES];
    [super activate:exclusive];
}

@end
