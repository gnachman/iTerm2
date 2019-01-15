//
//  iTermOnboardingWindowController.h
//  iTerm2
//
//  Created by George Nachman on 1/13/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermOnboardingWindowController : NSWindowController

+ (BOOL)shouldBeShown;
+ (void)suppressFutureShowings;
+ (BOOL)previousLaunchVersionImpliesShouldBeShown;

@end

NS_ASSUME_NONNULL_END
