//
//  iTermSplitViewAnimation.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/2/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// For a good laugh at Apple's expense, see https://stackoverflow.com/questions/6315091
@interface iTermSplitViewAnimation : NSAnimation

@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic) NSInteger dividerIndex;
@property (nonatomic) CGFloat startPosition;
@property (nonatomic) CGFloat endPosition;
@property (nonatomic, strong) void (^completion)(void);

- (instancetype)initWithSplitView:(NSSplitView *)splitView
                   dividerAtIndex:(NSInteger)dividerIndex
                             from:(CGFloat)startPosition
                               to:(CGFloat)endPosition
                         duration:(NSTimeInterval)duration
                       completion:(void (^ _Nullable)(void))completion;
@end


NS_ASSUME_NONNULL_END
