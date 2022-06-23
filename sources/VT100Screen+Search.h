//
//  VT100Screen+Search.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/16/22.
//

#import "VT100Screen.h"

@class FindContext;
@class SearchResult;

NS_ASSUME_NONNULL_BEGIN

@interface VT100Screen (Search)

- (void)setFindStringImpl:(NSString*)aString
         forwardDirection:(BOOL)direction
                     mode:(iTermFindMode)mode
              startingAtX:(int)x
              startingAtY:(int)y
               withOffset:(int)offset
                inContext:(FindContext *)context
          multipleResults:(BOOL)multipleResults;

- (BOOL)continueFindAllResultsImpl:(NSMutableArray<SearchResult *> *)results
                          rangeOut:(NSRange *)rangePtr
                         inContext:(FindContext *)context
                     rangeSearched:(VT100GridAbsCoordRange *)rangeSearched;

#pragma mark - Tail Find

// Save the position of the current search so that tail find can later begin from here.
- (void)saveFindContextAbsPosImpl;


// For tail find. Updates the find context with the saved start location.
- (void)restoreSavedPositionToFindContextImpl:(FindContext *)context;

// Record the location of the last position in the buffer so that later on tail find can begin from
// that point.
- (void)storeLastPositionInLineBufferAsFindContextSavedPositionImpl;

@end

NS_ASSUME_NONNULL_END
