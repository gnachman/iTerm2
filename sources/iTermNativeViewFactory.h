//
//  iTermNativeViewFactory.h
//  iTerm2
//
//  Created by George Nachman on 3/1/16.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermNativeViewController.h"

@interface iTermNativeViewFactory : NSObject

+ (iTermNativeViewController *)nativeViewControllerWithDescriptor:(NSString *)descriptor;

@end
