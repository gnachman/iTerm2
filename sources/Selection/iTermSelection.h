//
//  iTermSelection.h
//  iTerm
//
//  Created by George Nachman on 2/10/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

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
// Returns range of (parenthesized phrase) starting or ending at coord, or
// -1,-1,-1,-1 if none.
- (VT100GridAbsWindowedRange)selectionAbsRangeForParentheticalAt:(VT100GridAbsCoord)coord;

// Returns range of word including coord.
- (VT100GridAbsWindowedRange)selectionAbsRangeForWordAt:(VT100GridAbsCoord)coord;

// Returns range of smart selection at coord.
- (VT100GridAbsWindowedRange)selectionAbsRangeForSmartSelectionAt:(VT100GridAbsCoord)absCoord;

// Returns range of full wrapped line at coord.
- (VT100GridAbsWindowedRange)selectionAbsRangeForWrappedLineAt:(VT100GridAbsCoord)absCoord;

// Returns range of single line at coord.
- (VT100GridAbsWindowedRange)selectionAbsRangeForLineAt:(VT100GridAbsCoord)absCoord;

// Returns the x range of trailing nulls on a line.
- (VT100GridRange)selectionRangeOfTerminalNullsOnAbsoluteLine:(long long)absLineNumber;

// Returns the coordinate of the coordinate just before coord.
- (VT100GridAbsCoord)selectionPredecessorOfAbsCoord:(VT100GridAbsCoord)absCoord;

// Returns the width of the viewport (total columns in session).
- (int)selectionViewportWidth;

- (long long)selectionTotalScrollbackOverflow;

// Returns the indexes of cells on the given line containing the given
// (non-complex) character. Conformers may return nil when `line` is out of
// the current scrollback range (PTYTextView does this for absLine values
// that fall outside [totalScrollbackOverflow, +INT_MAX]).
- (nullable NSIndexSet *)selectionIndexesOnAbsoluteLine:(long long)line
                                    containingCharacter:(unichar)c
                                                inRange:(NSRange)range;

// Maps a VISUAL column range on a line to the set of LOGICAL cell indexes it
// covers. Identity when the line is not bidi-reordered. Used by visual
// (what-you-see) character selections on bidi lines: the live range stores
// visual columns, and this converts them for highlighting and for building
// the final logical subselections.
- (NSIndexSet *)selectionLogicalIndexesForVisualRange:(NSRange)visualRange
                                       onAbsoluteLine:(long long)line;

// Whether the line lays out right-to-left (right-justified with its reading
// start at the visual right edge). Determines which side of a multi-line
// visual selection's first and last lines is open.
- (BOOL)selectionParagraphIsRTLOnAbsoluteLine:(long long)line;

- (void)liveSelectionDidEnd;

@end

// Represents a single region of selected text, in either a continuous range or in a box (depending
// on selectionMode).
@interface iTermSubSelection : NSObject <NSCopying>

@property(nonatomic, assign) VT100GridAbsWindowedRange absRange;
@property(nonatomic, assign) iTermSelectionMode selectionMode;
@property(nonatomic, assign) BOOL connected;  // If connected, no newline occurs before the next sub
@property(nonatomic, assign) BOOL originatedFromBoxSelection;  // Decomposed from a box selection
@property(nonatomic, assign) VT100GridRange boxColumnBounds;  // Original column bounds when originatedFromBoxSelection

+ (instancetype)subSelectionWithAbsRange:(VT100GridAbsWindowedRange)range
                                    mode:(iTermSelectionMode)mode
                                   width:(int)width;
- (BOOL)containsAbsCoord:(VT100GridAbsCoord)coord;

@end

// Represents multiple discontiguous regions of selected text.
@interface iTermSelection : NSObject <NSCopying>

@property(nullable, nonatomic, assign) id<iTermSelectionDelegate> delegate;

// If set, the selection is currently being extended.
@property(nonatomic, readonly) BOOL extending;

// How to perform selection.
@property(nonatomic, assign) iTermSelectionMode selectionMode;

// Does the selection range's start come after its end? Not meaningful for box
// selections.
@property(nonatomic, readonly) BOOL liveRangeIsFlipped;

// YES when the live range's x coordinates are VISUAL columns (a character drag
// with bidi enabled). NO for word/line/box modes and for an EXTEND that restored
// its range from a committed (logical) subselection. Callers that feed a mouse
// endpoint into the live range use this to decide whether to convert the visual
// mouse column to logical first.
@property(nonatomic, readonly) BOOL liveRangeIsVisual;

// The range of selections. May be flipped.
@property(nonatomic, readonly) VT100GridAbsWindowedRange liveRange;

// A selection is in progress.
@property(nonatomic, readonly) BOOL live;

// All sub selections, including the live one if applicable.
@property(nonatomic, readonly) NSArray<iTermSubSelection *> *allSubSelections;

// Like allSubSelections, but an in-progress VISUAL character-drag live range
// (bidi) is reported in LOGICAL coordinates. Use this for external consumers
// that read the selection as logical buffer coordinates (the scripting API), so
// a mid-drag read on a right-to-left line does not expose raw visual columns.
// allSubSelections keeps the raw live range for internal geometry.
@property(nonatomic, readonly) NSArray<iTermSubSelection *> *logicalSubSelections;

// The last range, including the live one if applicable. Ranges are ordered by endpoint.
// The range will be -1,-1,-1,-1 if there are none.
@property(nonatomic, readonly) VT100GridAbsWindowedRange lastAbsRange;

// The first range, including the live one if applicable. Ranges are ordered by startpoint.
// The range will be -1,-1,-1,-1 if ther are none.
@property(nonatomic, readonly) VT100GridAbsWindowedRange firstAbsRange;

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
@property(nonatomic, readonly) VT100GridAbsCoordRange spanningAbsRange;

// Has clearColumnWindowForLiveSelection been called?
@property(nonatomic, readonly) BOOL haveClearedColumnWindow;

@property(nonatomic, readonly) int approximateNumberOfLines;

// Returns the debugging name for a selection mode.
+ (NSString *)nameForMode:(iTermSelectionMode)mode;

// Start a new selection, erasing the old one. Enters live selection.
// Set |resume| to continue the previous live selection in a new mode.
// Set |append| to create a new (possibly discontinuous) selection rather than replacing the
// existing set of subselections.
// Start a new selection, erasing the old one. Enters live selection.
- (void)beginSelectionAtAbsCoord:(VT100GridAbsCoord)absCoord
                            mode:(iTermSelectionMode)mode
                          resume:(BOOL)resume
                          append:(BOOL)append;

// Start extending an existing election, moving an endpoint to the given
// coordinate in a way appropriate for the selection mode. Enters live selection.
- (void)beginExtendingSelectionAt:(VT100GridAbsCoord)coord;

// During live selection, adjust the endpoint.
- (BOOL)moveSelectionEndpointTo:(VT100GridAbsCoord)coord NS_SWIFT_NAME(moveEndpoint(to:));

// End live selection.
- (void)endLiveSelection;

// Convert the live selection to not use a column window.
- (void)clearColumnWindowForLiveSelection;

// Remove selection.
- (void)clearSelection;

// Update ranges for new scrollback overflow.
- (void)scrollbackOverflowDidChange;

// Indicates if the selection contains the coordinate.
- (BOOL)containsAbsCoord:(VT100GridAbsCoord)coord;

// Add a range to the set of selections.
- (void)addSubSelection:(iTermSubSelection *)sub;

// Replace the selection with a single committed subselection covering a LOGICAL
// range. Use this for programmatic callers that already hold logical coordinates
// (find, "select last command output", VoiceOver set-range, smart select).
// Driving a character-mode live selection instead would, with bidi enabled,
// reinterpret the coordinates as VISUAL columns (the live range is visual for
// character mode) and mis-select on right-to-left lines.
//
// Only for NON-EXPANDING modes (character, smart): the range is committed as
// given (clamped to width). Line and box modes expand a range to whole lines /
// column bounds only while it is LIVE, so they must use the live path instead.
- (void)setSelectedLogicalRange:(VT100GridAbsWindowedRange)range
                           mode:(iTermSelectionMode)mode;

// Build a committed-logical range (suitable for setSelectedLogicalRange:mode:)
// from two VISUAL coordinates, converting BOTH to logical via `converter` (a
// no-op on non-reordered lines). Used by find-on-page shift-extend, where the
// find cursor and the click are both visual. Exposed for testing.
+ (VT100GridAbsWindowedRange)logicalAbsRangeFromVisualStart:(VT100GridCoord)visualStart
                                                 visualEnd:(VT100GridCoord)visualEnd
                                                  overflow:(long long)overflow
                                                 converter:(VT100GridCoord (^)(VT100GridCoord))converter;

// This is much faster than repeated calls to addSubSelection:.
- (void)addSubSelections:(NSArray<iTermSubSelection *> *)subSelectionArray;

// Returns the indexes of characters selected on a given line.
- (NSIndexSet *)selectedIndexesOnAbsoluteLine:(long long)line;

// Per-line visual index span of a character-mode range, honoring the column
// window. Drives the live highlight and the endLive decomposition. Exposed for
// testing.
- (NSRange)visualRangeOfIndexesInAbsRange:(VT100GridAbsWindowedRange)range
                           onAbsoluteLine:(long long)line;

// Calls the block for each selected range.
- (void)enumerateSelectedAbsoluteRanges:(void (^ NS_NOESCAPE)(VT100GridAbsWindowedRange range, BOOL *stop, BOOL eol))block;

// Changes the first/last range.
- (void)setFirstAbsRange:(VT100GridAbsWindowedRange)firstRange mode:(iTermSelectionMode)mode;
- (void)setLastAbsRange:(VT100GridAbsWindowedRange)lastRange mode:(iTermSelectionMode)mode;

// Convert windowed selections to multiple discontinuous non-windowed selections.
// If a subselection's window spans 0 to width, then it is windowless.
- (void)removeWindowsWithWidth:(int)width;

// Augments the "real" selection by adding TAB_FILLER characters preceding a selected TAB. Used for
// display purposes. Removes selected TAB_FILLERS that aren't followed by a selected TAB.
- (NSIndexSet *)selectedIndexesIncludingTabFillersInAbsoluteLine:(long long)y;

// Load selection from serialized dict
- (void)setFromDictionaryValue:(NSDictionary *)dict
                         width:(int)width
       totalScrollbackOverflow:(long long)totalScrollbackOverflow;

// Serialized.
- (NSDictionary *)dictionaryValueWithYOffset:(int)yOffset
                     totalScrollbackOverflow:(long long)totalScrollbackOverflow;

// Utility methods
- (BOOL)absCoord:(VT100GridAbsCoord)a isBeforeAbsCoord:(VT100GridAbsCoord)b;

@end

NS_ASSUME_NONNULL_END
