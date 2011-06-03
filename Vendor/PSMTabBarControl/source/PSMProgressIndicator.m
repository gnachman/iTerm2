//
//  PSMProgressIndicator.m
//  PSMTabBarControl
//
//  Created by John Pannell on 2/23/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMProgressIndicator.h"

@implementation PSMProgressIndicator

// overrides to make tab bar control re-layout things if status changes
- (void)setHidden:(BOOL)flag
{
    [super setHidden:flag];
    [(PSMTabBarControl *)[self superview] update];
}

@end
