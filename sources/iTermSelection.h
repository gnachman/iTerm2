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

typedef NS_ENUM(NSInteger, iTermSelectionMode) {
    kiTermSelectionModeCharacter,
    kiTermSelectionModeWord,
    kiTermSelectionModeLine,
    kiTermSelectionModeSmart,
    kiTermSelectionModeBox,
    kiTermSelectionModeWholeLine
};

@protocol iTermSelectionDelegate <NSObject>

- (void)selectionDidChange:(iTermSelection *)selection;
// Returns range of (parenthesized phrase) startin or ending at coord, or
// -1,-1,-1,-1 if none.
- (VT100GridWindowedRange)selectionRangeForParentheticalAt:(VT100GridCoord)coord;

// Returns range of word including coord.
- (VT100GridWindowedRange)selectionRangeForWordAt:(VT100GridCoord)coord;

// Returns range of smart selection at coord.
- (VT100GridWindowedRange)selectionRangeForSmartSelectionAt:(VT100GridCoord)coord;

// Returns range of full wrapped line at coord.
- (VT100GridWindowedRange)selectionRangeForWrappedLineAt:(VT100GridCoord)coord;

// Returns range of single line at coord.
- (VT100GridWindowedRange)selectionRangeForLineAt:(VT100GridCoord)coord;

// Returns the x range of trailing nulls on a line.
- (VT100GridRange)selectionRangeOfTerminalNullsOnLine:(int)lineNumber;

// Returns the coordinate of the coordinate just before coord.
- (VT100GridCoord)selectionPredecessorOfCoord:(VT100GridCoord)coord;

// Returns the width of the viewport (total columns in session).
- (int)selectionViewportWidth;

// Returns the indexes of cells on the given line containing the given (non-complex) character.
- (NSIndexSet *)selectionIndexesOnLine:(int)line
                   containingCharacter:(unichar)c
                               inRange:(NSRange)range;

@end

// Represents a single region of selected text, in either a continuous range or in a box (depending
// on selectionMode).
@interface iTermSubSelection : NSObject <NSCopying>

@property(nonatomic, assign) VT100GridWindowedRange range;
@property(nonatomic, assign) iTermSelectionMode selectionMode;
@property(nonatomic, assign) BOOL connected;  // If connected, no newline occurs before the next sub

+ (instancetype)subSelectionWithRange:(VT100GridWindowedRange)range
                                 mode:(iTermSelectionMode)mode;
- (BOOL)containsCoord:(VT100GridCoord)coord;

@end

// Represents multiple discontiguous regions of selected text.
@interface iTermSelection : NSObject <NSCopying>

@property(nonatomic, assign) id<iTermSelectionDelegate> delegate;

// If set, the selection is currently being extended.
@property(nonatomic, readonly) BOOL extending;

// How to perform selection.
@property(nonatomic, assign) iTermSelectionMode selectionMode;

// Does the selection range's start come after its end? Not meaningful for box
// selections.
@property(nonatomic, readonly) BOOL liveRangeIsFlipped;

// The range of selections. May be flipped.
@property(nonatomic, readonly) VT100GridWindowedRange liveRange;

// A selection is in progress.
@property(nonatomic, readonly) BOOL live;

// All sub selections, including the live one if applicable.
@property(nonatomic, readonly) NSArray *allSubSelections;

// The last range, including the live one if applicable. Ranges are ordered by endpoint.
// The range will be -1,-1,-1,-1 if there are none.
@property(nonatomic, readonly) VT100GridWindowedRange lastRange;

// The first range, including the live one if applicable. Ranges are ordered by startpoint.
// The range will be -1,-1,-1,-1 if ther are none.
@property(nonatomic, readonly) VT100GridWindowedRange firstRange;

// If set, then the current live selection can be resumed in a different mode.
// This is used when a range is created by a single click which then becomes a double,
// triple, etc. click.
@property(nonatomic, assign) BOOL resumable;

// Was the append property used on the last selection?
@property(nonatomic, assign) BOOL appending;

// Indicates if there is a non-empty selection.
@property(nonatomic, readonly) BOOL hasSelection;

// Length of the selection in characters.
@property(nonatomic, readonly) long long length;

// Range from the earliest point to the latest point of all selection ranges.
@property(nonatomic, readonly) VT100GridCoordRange spanningRange;

// Returns the debugging name for a selection mode.
+ (NSString *)nameForMode:(iTermSelectionMode)mode;

// Start a new selection, erasing the old one. Enters live selection.
// Set |resume| to continue the previous live selection in a new mode.
// Set |append| to create a new (possibly discontinuous) selection rathern than replacing the
// existing set of subselections.
// Start a new selection, erasing the old one. Enters live selection.
- (void)beginSelectionAt:(VT100GridCoord)coord
                    mode:(iTermSelectionMode)mode
                  resume:(BOOL)resume
                  append:(BOOL)append;

// Start extending an existing election, moving an endpoint to the given
// coordinate in a way appropriate for the selection mode. Enters live selection.
- (void)beginExtendingSelectionAt:(VT100GridCoord)coord;

// During live selection, adjust the endpoint.
- (void)moveSelectionEndpointTo:(VT100GridCoord)coord;

// End live selection.
- (void)endLiveSelection;

// Remove selection.
- (void)clearSelection;

// Subtract numLines from y coordinates.
- (void)moveUpByLines:(int)numLines;

// Indicates if the selection contains the coordinate.
- (BOOL)containsCoord:(VT100GridCoord)coord;

// Add a range to the set of selections.
- (void)addSubSelection:(iTermSubSelection *)sub;

// This is much faster than repeated calls to addSubSelection:.
- (void)addSubSelections:(NSArray<iTermSubSelection *> *)subSelectionArray;

// Returns the indexes of characters selected on a given line.
- (NSIndexSet *)selectedIndexesOnLine:(int)line;

// Calls the block for each selected range.
- (void)enumerateSelectedRanges:(void (^)(VT100GridWindowedRange range, BOOL *stop, BOOL eol))block;

// Changes the first/last range.
- (void)setFirstRange:(VT100GridWindowedRange)firstRange mode:(iTermSelectionMode)mode;
- (void)setLastRange:(VT100GridWindowedRange)lastRange mode:(iTermSelectionMode)mode;

// Convert windowed selections to multiple discontinuous non-windowed selections.
// If a subselection's window spans 0 to width, then it is windowless.
- (void)removeWindowsWithWidth:(int)width;

// Augments the "real" selection by adding TAB_FILLER characters preceding a selected TAB. Used for
// display purposes. Removes selected TAB_FILLERS that aren't followed by a selected TAB.
- (NSIndexSet *)selectedIndexesIncludingTabFillersInLine:(int)y;

// Load selection from serialized dict
- (void)setFromDictionaryValue:(NSDictionary *)dict;

// Serialized.
- (NSDictionary *)dictionaryValueWithYOffset:(int)yOffset;

// Utility methods
- (BOOL)coord:(VT100GridCoord)a isBeforeCoord:(VT100GridCoord)b;

@end
