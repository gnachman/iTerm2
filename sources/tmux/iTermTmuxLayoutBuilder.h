//
//  iTermTmuxLayoutBuilder.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/8/19.
//

#import <Foundation/Foundation.h>
#import "TmuxLayoutParser.h"
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

// Grows the leaves on the affected window edge by one row so the layout and
// clientSize reported to tmux include the row tmux reserves for
// pane-border-status. This is the inverse of the inbound correction in
// -[TmuxLayoutParser parseTree:adjustedForPaneBorderStatus:] and keeps iTerm2
// from shrinking the window a row at a time (issue 12925). No-op when off.
- (void)adjustForPaneBorderStatus:(iTermTmuxPaneBorderStatus)status;

@end

NS_ASSUME_NONNULL_END
