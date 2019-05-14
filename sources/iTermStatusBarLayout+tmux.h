//
//  iTermStatusBarLayout+tmux.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/26/18.
//

#import "iTermStatusBarLayout.h"

NS_ASSUME_NONNULL_BEGIN

@class TmuxController;

@interface iTermStatusBarLayout (tmux)

+ (instancetype)tmuxLayoutWithController:(TmuxController *)controller
                                   scope:(nullable iTermVariableScope *)scope
                                  window:(int)window;
+ (BOOL)shouldOverrideLayout:(NSDictionary *)layout;

@end

NS_ASSUME_NONNULL_END
