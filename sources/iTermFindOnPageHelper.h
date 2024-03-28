//
//  iTermFindOnPageHelper.h
//  iTerm2
//
//  Created by George Nachman on 11/24/14.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermFindDriver.h"
#import "iTermSearchResultsMinimapView.h"
#import "VT100GridTypes.h"

@class FindContext;
@class iTermExternalSearchResult;
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
                multipleResults:(BOOL)multipleResults
                   absLineRange:(NSRange)absLineRange;

// Save the absolute position in the find context.
- (void)findOnPageSaveFindContextAbsPos;

// Find more, fill in results.
- (BOOL)continueFindAllResults:(NSMutableArray *)results
                      rangeOut:(NSRange *)rangePtr
                     inContext:(FindContext *)context
                  absLineRange:(NSRange)absLineRange
                 rangeSearched:(VT100GridAbsCoordRange *)rangeSearched;

// Select a range.
- (void)findOnPageSelectRange:(VT100GridCoordRange)range wrapped:(BOOL)wrapped;
- (VT100GridCoordRange)findOnPageSelectExternalResult:(iTermExternalSearchResult *)result;

// Show that the search wrapped.
- (void)findOnPageDidWrapForwards:(BOOL)directionIsForwards;

// Ensure a range is visible.
- (void)findOnPageRevealRange:(VT100GridCoordRange)range;

// Indicate that the search failed.
- (void)findOnPageFailed;

- (long long)findOnPageOverflowAdjustment;
- (NSRange)findOnPageRangeOfVisibleLines;
- (void)findOnPageLocationsDidChange;
- (void)findOnPageSelectedResultDidChange;

// Call -addExternalResults:width:
- (void)findOnPageHelperSearchExternallyFor:(NSString *)query
                                       mode:(iTermFindMode)mode;
- (void)findOnPageHelperRemoveExternalHighlights;
- (void)findOnPageHelperRequestRedraw;
- (void)findOnPageHelperRemoveExternalHighlightsFrom:(iTermExternalSearchResult *)externalSearchResult;
@end

typedef NS_ENUM(NSUInteger, FindCursorType) {
    FindCursorTypeInvalid,
    FindCursorTypeCoord,
    FindCursorTypeExternal
};

@interface FindCursor: NSObject
@property (nonatomic, readonly) FindCursorType type;
@property (nonatomic, readonly) VT100GridAbsCoord coord;
@property (nonatomic, strong, readonly) iTermExternalSearchResult *external;
@end

@interface iTermFindOnPageHelper : NSObject<iTermSearchResultsMinimapViewDelegate>

@property(nonatomic, readonly) BOOL findInProgress;
@property(nonatomic, assign) NSView<iTermFindOnPageHelperDelegate> *delegate;
@property(nonatomic, readonly) NSDictionary *highlightMap;
@property(nonatomic, readonly) FindContext *copiedContext;
@property(nonatomic, readonly) NSOrderedSet<SearchResult *> *searchResults;
@property(nonatomic, readonly) NSInteger numberOfSearchResults;
@property(nonatomic, readonly) NSInteger currentIndex;
// This is used to select which search result should be highlighted. If searching forward, it'll
// be after the find cursor; if searching backward it will be before the find cursor.
@property(nonatomic, readonly) FindCursor *findCursor;
// Length of 0 means no range is selected. Otherwise, only this range of lines is searched.
@property(nonatomic) NSRange absLineRange;

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
// force: Begin a new search even if the string and mode are unchanged.
- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
              mode:(iTermFindMode)mode
        withOffset:(int)offset
           context:(FindContext *)findContext
     numberOfLines:(int)numberOfLines
totalScrollbackOverflow:(long long)totalScrollbackOverflow
scrollToFirstResult:(BOOL)scrollToFirstResult
              force:(BOOL)force;

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
            rangeOut:(NSRange *)rangePtr
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
- (void)enumerateSearchResultsInRangeOfLines:(NSRange)range
                                       block:(void (^ NS_NOESCAPE)(SearchResult *result))block;
- (void)overflowAdjustmentDidChange;
- (void)addExternalResults:(NSArray<iTermExternalSearchResult *> *)externalResults
                     width:(int)width;

@end
