//
//  iTermCancelable.h
//  iTerm2
//
//  Created by George Nachman on 2/24/22.
//

#import <Foundation/Foundation.h>

@protocol iTermCancelable<NSObject>
- (void)cancelOperation;
@end

// Invokes the block on cancellation.
@interface iTermBlockCanceller: NSObject<iTermCancelable>
@property (nonatomic, readonly, copy) void (^block)(void);
- (instancetype)initWithBlock:(void (^)(void))block;
@end

