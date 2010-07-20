//
//  PSMProgressIndicator.h
//  PSMTabBarControl
//
//  Created by John Pannell on 2/23/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PSMTabBarControl.h"


@interface PSMProgressIndicator : NSProgressIndicator {

}

@end

@interface PSMTabBarControl (LayoutPlease)

- (void)update;

@end