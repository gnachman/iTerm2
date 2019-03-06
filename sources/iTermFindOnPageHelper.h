//
//  iTermFindOnPageHelper.h
//  iTerm2
//
//  Created by George Nachman on 11/24/14.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermFindDriver.h"
#import "VT100GridTypes.h"

@class FindContext;
@class iTermSubSelection;
@class SearchResult;

@protocol iTermFindOnPageHelperDelegate <NSObject>

// Actually perform a search.
- (void)findOnPageSetFindString:(NSString*)aString
               forwardDirection:(BOOL)direction
                           mode:(iTermFindMode)mode
                    startingAtX:(int)x
                    startingAtY:(int)y
                     withOffset:(int)offset
                      inContext:(FindContext*)context
                multipleResults:(BOOL)multipleResults;

// Save the absolute position in the find context.
- (void)findOnPageSaveFindContextAbsPos;

// Find more, fill in results.
- (BOOL)continueFindAllResults:(NSMutableArray *)results
                     inContext:(FindContext*)context;

// Select a range.
- (void)findOnPageSelectRange:(VT100GridCoordRange)range wrapped:(BOOL)wrapped;

// Show that the search wrapped.
- (void)findOnPageDidWrapForwards:(BOOL)directionIsForwards;

// Ensure a range is visible.
- (void)findOnPageRevealRange:(VT100GridCoordRange)range;

// Indicate that the search failed.
- (void)findOnPageFailed;

@end

@interface iTermFindOnPageHelper : NSObject

@property(nonatomic, readonly) BOOL findInProgress;
@property(nonatomic, assign) NSView<iTermFindOnPageHelperDelegate> *delegate;
@property(nonatomic, readonly) NSDictionary *highlightMap;
@property(nonatomic, readonly) BOOL haveFindCursor;
@property(nonatomic, readonly) VT100GridAbsCoord findCursorAbsCoord;
@property(nonatomic, readonly) FindContext *copiedContext;
@property(nonatomic, readonly) NSOrderedSet<SearchResult *> *searchResults;

// Begin a new search.
//
// aString: The string to search for.
// direction: YES to search forwards, NO to search backwards. In practice the search always happens
//   backwards but direction decides which result to highlight first.
// mode: search mode (case sensitivity, regex)
// offset: Amount to add to findCursor for where to begin searching (used for "find next" to begin
//   the search just after the current result)
// findContext: The context to use to hold results.
// numberOfLines: Number of lines in the data to be searched
// totalScrollbackOverflow: Number of lines lost to scrollback history (used to calculate absolute
//   line numbers).
- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
              mode:(iTermFindMode)mode
        withOffset:(int)offset
           context:(FindContext *)findContext
     numberOfLines:(int)numberOfLines
totalScrollbackOverflow:(long long)totalScrollbackOverflow
scrollToFirstResult:(BOOL)scrollToFirstResult;

// Remove all highlight data.
- (void)clearHighlights;

// Reset the copied find context. This will prevent tail search from running in the future.
- (void)resetCopiedFindContext;

// Erase the find cursor.
- (void)resetFindCursor;

// Highlights a search result.
- (void)addSearchResult:(SearchResult *)searchResult width:(int)width;

// Search the next block (calling out to the delegate to do the real work) and update highlights and
// search results.
- (BOOL)continueFind:(double *)progress
             context:(FindContext *)context
               width:(int)width
       numberOfLines:(int)numberOfLines
  overflowAdjustment:(long long)overflowAdjustment;

// Remove highlights in a range of lines.
- (void)removeHighlightsInRange:(NSRange)range;
- (void)removeSearchResultsInRange:(NSRange)range;
- (void)removeAllSearchResults;

// Sets the location to start searching. TODO: Currently this only works for find next/prev.
- (void)setStartPoint:(VT100GridAbsCoord)startPoint;

- (NSRange)rangeOfSearchResultsInRangeOfLines:(NSRange)range;

@end
