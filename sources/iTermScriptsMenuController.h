//
//  iTermScriptsMenuController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermScriptsMenuController : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMenu:(NSMenu *)menu;
- (void)build;
- (BOOL)runAutoLaunchScriptsIfNeeded;
- (void)revealScriptsInFinder;

@end

NS_ASSUME_NONNULL_END

