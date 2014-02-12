//
//  iTermSelection.h
//  iTerm
//
//  Created by George Nachman on 2/10/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100GridTypes.h"

@class iTermSelection;

typedef enum {
    kiTermSelectionModeCharacter,
    kiTermSelectionModeWord,
    kiTermSelectionModeLine,
    kiTermSelectionModeSmart,
    kiTermSelectionModeBox,
    kiTermSelectionModeWholeLine
} iTermSelectionMode;

@protocol iTermSelectionDelegate <NSObject>

- (void)selectionDidChange:(iTermSelection *)selection;

@end

// Represents the region of selected text.
@interface iTermSelection : NSObject <NSCopying>

@property(nonatomic, assign) id<iTermSelectionDelegate> delegate;
@property(nonatomic, readonly) BOOL extending;
@property(nonatomic, assign) iTermSelectionMode selectionMode;
@property(nonatomic, readonly) BOOL isFlipped;
@property(nonatomic, assign) VT100GridCoordRange selectedRange;

- (void)beginLiveSelectionAt:(VT100GridCoord)coord
                      extend:(BOOL)extend
                        mode:(iTermSelectionMode)mode;
- (void)updateLiveSelectionWithCoord:(VT100GridCoord)coord;
- (void)updateLiveSelectionWithRange:(VT100GridCoordRange)range;
- (void)updateLiveSelectionToLine:(int)y width:(int)width;
- (void)updateLiveSelectionToRangeOfLines:(VT100GridRange)lineRange width:(int)width;
- (void)updateLiveSelectionWithRange:(VT100GridCoordRange)range
                         rangeToKeep:(VT100GridCoordRange)rangeToKeep;  // On direction reversal, preserve this range.
- (void)endLiveSelection;
- (void)clearSelection;
- (void)moveUpByLines:(int)numLines;
- (BOOL)hasSelection;
- (BOOL)containsCoord:(VT100GridCoord)coord;
- (long long)lengthGivenWidth:(int)width;

@end
