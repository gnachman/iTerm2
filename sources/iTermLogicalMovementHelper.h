//
//  iTermLogicalMovementHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/23/19.
//

#import <Foundation/Foundation.h>
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermSelection;
@class iTermTextExtractor;

typedef NS_ENUM(NSInteger, PTYTextViewSelectionEndpoint) {
    kPTYTextViewSelectionEndpointStart,
    kPTYTextViewSelectionEndpointEnd
};

typedef NS_ENUM(NSInteger, PTYTextViewSelectionExtensionDirection) {
    kPTYTextViewSelectionExtensionDirectionLeft,
    kPTYTextViewSelectionExtensionDirectionRight,

    // These ignore the unit and are simple movements.
    kPTYTextViewSelectionExtensionDirectionUp,
    kPTYTextViewSelectionExtensionDirectionDown,
    kPTYTextViewSelectionExtensionDirectionStartOfLine,
    kPTYTextViewSelectionExtensionDirectionEndOfLine,
    kPTYTextViewSelectionExtensionDirectionTop,
    kPTYTextViewSelectionExtensionDirectionBottom,
    kPTYTextViewSelectionExtensionDirectionStartOfIndentation,
};

typedef NS_ENUM(NSInteger, PTYTextViewSelectionExtensionUnit) {
    kPTYTextViewSelectionExtensionUnitCharacter,
    kPTYTextViewSelectionExtensionUnitWord,
    kPTYTextViewSelectionExtensionUnitLine,
    kPTYTextViewSelectionExtensionUnitMark,
    kPTYTextViewSelectionExtensionUnitBigWord,
};

@protocol iTermLogicalMovementHelperDelegate<NSObject>
// return -1 if none
- (long long)lineNumberOfMarkAfterAbsLine:(long long)line;

// return -1 if none
- (long long)lineNumberOfMarkBeforeAbsLine:(long long)line;

@end

@interface iTermLogicalMovementHelper : NSObject

@property (nonatomic, weak) id<iTermLogicalMovementHelperDelegate> delegate;

- (instancetype)initWithTextExtractor:(iTermTextExtractor *)textExtractor
                            selection:(iTermSelection *)selection
                     cursorCoordinate:(VT100GridAbsCoord)cursorCoord
                                width:(int)width
                        numberOfLines:(long long)numberOfLines
              totalScrollbackOverflow:(long long)totalScrollbackOverflow NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (VT100GridAbsCoordRange)moveSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint
                                    inDirection:(PTYTextViewSelectionExtensionDirection)direction
                                             by:(PTYTextViewSelectionExtensionUnit)unit;

- (VT100GridAbsWindowedRange)absRangeByExtendingRange:(VT100GridAbsWindowedRange)existingRange
                                             endpoint:(PTYTextViewSelectionEndpoint)endpoint
                                            direction:(PTYTextViewSelectionExtensionDirection)direction
                                            extractor:(iTermTextExtractor *)extractor
                                                 unit:(PTYTextViewSelectionExtensionUnit)unit;

@end

NS_ASSUME_NONNULL_END
