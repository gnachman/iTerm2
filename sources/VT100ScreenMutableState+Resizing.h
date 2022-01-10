//
//  VT100ScreenMutableState+Resizing.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/10/22.
//

#import "VT100ScreenMutableState.h"

@class iTermSelection;

NS_ASSUME_NONNULL_BEGIN

@interface VT100ScreenMutableState (Resizing)

#pragma mark - Private APIs (remove this once migration is done)

- (VT100GridSize)safeSizeForSize:(VT100GridSize)proposedSize;
- (BOOL)shouldSetSizeTo:(VT100GridSize)size;
- (void)sanityCheckIntervalsFrom:(VT100GridSize)oldSize note:(NSString *)note;
- (void)willSetSizeWithSelection:(iTermSelection *)selection;
- (int)appendScreen:(VT100Grid *)grid
       toScrollback:(LineBuffer *)lineBufferToUse
     withUsedHeight:(int)usedHeight
          newHeight:(int)newHeight;
- (VT100GridRun)runByTrimmingNullsFromRun:(VT100GridRun)run;
- (BOOL)trimSelectionFromStart:(VT100GridCoord)start
                           end:(VT100GridCoord)end
                      toStartX:(VT100GridCoord *)startPtr
                        toEndX:(VT100GridCoord *)endPtr;
- (LineBufferPositionRange *)positionRangeForCoordRange:(VT100GridCoordRange)range
                                           inLineBuffer:(LineBuffer *)lineBuffer
                                          tolerateEmpty:(BOOL)tolerateEmpty;
- (NSArray *)subSelectionTuplesWithUsedHeight:(int)usedHeight
                                    newHeight:(int)newHeight
                                    selection:(iTermSelection *)selection;
- (BOOL)intervalTreeObjectMayBeEmpty:(id<IntervalTreeObject>)note;
- (NSArray *)intervalTreeObjectsWithUsedHeight:(int)usedHeight
                                     newHeight:(int)newHeight
                                          grid:(VT100Grid *)grid
                                    lineBuffer:(LineBuffer *)realLineBuffer;
- (LineBuffer *)prepareToResizeInAlternateScreenMode:(NSArray **)altScreenSubSelectionTuplesPtr
                                 intervalTreeObjects:(NSArray **)altScreenNotesPtr
                                        hasSelection:(BOOL)couldHaveSelection
                                           selection:(iTermSelection *)selection
                                          lineBuffer:(LineBuffer *)realLineBuffer
                                          usedHeight:(int)usedHeight
                                             newSize:(VT100GridSize)newSize;
- (BOOL)convertRange:(VT100GridCoordRange)range
             toWidth:(int)newWidth
                  to:(VT100GridCoordRange *)resultPtr
        inLineBuffer:(LineBuffer *)lineBuffer
       tolerateEmpty:(BOOL)tolerateEmpty;

@end

NS_ASSUME_NONNULL_END
