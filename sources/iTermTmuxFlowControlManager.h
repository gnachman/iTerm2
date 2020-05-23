//
//  iTermTmuxFlowControlManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/23/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermTmuxFlowControlManager : NSObject

- (instancetype)initWithAcker:(void (^)(NSDictionary<NSNumber *, NSNumber *> *))acker NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)push;
- (void)pop;
- (void)addBytes:(NSInteger)count pane:(NSInteger)pane;

@end

NS_ASSUME_NONNULL_END
