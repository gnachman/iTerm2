//
//  iTermInitialDirectory+Tmux.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/14/19.
//

#import "iTermInitialDirectory.h"

@class iTermVariableScope;

NS_ASSUME_NONNULL_BEGIN

@interface iTermInitialDirectory (Tmux)

- (void)tmuxNewWindowCommandInSession:(nullable NSString *)session
                   recyclingSupported:(BOOL)recyclingSupported
                                scope:(iTermVariableScope *)scope
                           completion:(void (^)(NSString *))completion;

- (void)tmuxNewWindowCommandRecyclingSupported:(BOOL)recyclingSupported
                                         scope:(iTermVariableScope *)scope
                                    completion:(void (^)(NSString *))completion;

- (void)tmuxSplitWindowCommand:(int)wp
                    vertically:(BOOL)splitVertically
            recyclingSupported:(BOOL)recyclingSupported
                         scope:(iTermVariableScope *)scope
                    completion:(void (^)(NSString *))completion;

@end

NS_ASSUME_NONNULL_END
