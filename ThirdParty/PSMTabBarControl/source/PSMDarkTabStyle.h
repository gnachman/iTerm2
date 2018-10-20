//
//  PSMDarkTabStyle.h
//  iTerm
//
//  Created by Brian Mock on 10/28/14.
//
//

#import <Cocoa/Cocoa.h>
#import "PSMTabStyle.h"
#import "PSMYosemiteTabStyle.h"

@interface PSMDarkTabStyle : PSMYosemiteTabStyle<PSMTabStyle>
+ (NSColor *)tabBarColorWhenKeyAndActive:(BOOL)keyAndActive;
@end
