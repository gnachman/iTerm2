//
//  iTermCopyModeState.h
//  iTerm2
//
//  Created by George Nachman on 4/29/17.
//
//

#import <Foundation/Foundation.h>

#import "iTermSelection.h"
#import "VT100GridTypes.h"

@class PTYTextView;

@protocol iTermCopyModeStateProtocol<NSObject>
@property (nonatomic) BOOL selecting;
@property (nonatomic) iTermSelectionMode mode;

- (BOOL)moveBackwardWord;
- (BOOL)moveForwardWord;

- (BOOL)moveBackwardBigWord;
- (BOOL)moveForwardBigWord;

- (BOOL)moveLeft;
- (BOOL)moveRight;

- (BOOL)moveUp;
- (BOOL)moveDown;

- (BOOL)moveToStartOfNextLine;

- (BOOL)pageUp;
- (BOOL)pageDown;
- (BOOL)pageUpHalfScreen;
- (BOOL)pageDownHalfScreen;

- (BOOL)previousMark;
- (BOOL)nextMark;

- (BOOL)moveToStart;
- (BOOL)moveToEnd;

- (BOOL)moveToStartOfIndentation;

- (BOOL)moveToBottomOfVisibleArea;
- (BOOL)moveToMiddleOfVisibleArea;
- (BOOL)moveToTopOfVisibleArea;

- (BOOL)moveToStartOfLine;
- (BOOL)moveToEndOfLine;

- (void)swap;

- (BOOL)scrollUp;
- (BOOL)scrollDown;

@optional
- (void)performAsynchronously:(void (^)(void))block completion:(void (^)(BOOL))completion;

@end

@interface iTermCopyModeState : NSObject<iTermCopyModeStateProtocol>

@property (nonatomic) VT100GridCoord coord;
@property (nonatomic) VT100GridCoord start;
@property (nonatomic) int numberOfLines;
@property (nonatomic, strong) PTYTextView *textView;
@property (nonatomic) BOOL selecting;
@property (nonatomic) iTermSelectionMode mode;

@end
