//
//  iTermURLActionFactory+Testing.h
//  iTerm2
//
//  Synchronous seams into the ⌘-click URL-detection machinery, exposed for unit tests.
//

#import <Foundation/Foundation.h>

#import "VT100GridTypes.h"
#import "iTermURLActionFactory.h"

@class iTermTextExtractor;

NS_ASSUME_NONNULL_BEGIN

@interface iTermURLActionFactory (Testing)

// The URL-like string ⌘-click detects at `coord`, including the same forward-window extension the
// asynchronous ⌘-click path applies. This is the synchronous URL-extraction core of
// -urlActionForURLLike (capture the prefix/suffix around the click, extend past the capture window
// if the run reaches its edge, then pull the URL-like substring out of the joined text) with none of
// the scheme guessing or openability probing that follows. Returns nil if no URL is found.
+ (nullable NSString *)urlLikeStringAtCoord:(VT100GridCoord)coord
                        respectHardNewlines:(BOOL)respectHardNewlines
                                  extractor:(iTermTextExtractor *)extractor
    NS_SWIFT_NAME(urlLikeString(at:respectHardNewlines:extractor:));

@end

NS_ASSUME_NONNULL_END
