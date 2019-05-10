//
//  iTermTmuxLayoutBuilder.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/8/19.
//

#import <Foundation/Foundation.h>
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermTmuxLayoutBuilderNode : NSObject
@end

@interface iTermTmuxLayoutBuilderLeafNode : iTermTmuxLayoutBuilderNode
- (instancetype)initWithSessionOfSize:(VT100GridSize)size
                           windowPane:(int)windowPane;
@end

@interface iTermTmuxLayoutBuilderInteriorNode : iTermTmuxLayoutBuilderNode
- (instancetype)initWithVerticalDividers:(BOOL)verticalDividers;
- (void)addNode:(iTermTmuxLayoutBuilderNode *)node;
@end

@interface iTermTmuxLayoutBuilder : NSObject
@property (nonatomic, readonly) NSString *layoutString;
@property (nonatomic, readonly) VT100GridSize clientSize;

- (instancetype)initWithRootNode:(iTermTmuxLayoutBuilderNode *)node;

@end

NS_ASSUME_NONNULL_END
