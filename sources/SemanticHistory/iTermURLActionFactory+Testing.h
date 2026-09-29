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

// Whether +urlForUserSuppliedString:guessingScheme: would consider `url` openable. Consults
// profiles bound to schemes, the urlHandlerCommand advanced setting, and LaunchServices.
+ (BOOL)urlHasOpenableScheme:(NSURL *)url;

// Replaces the openability check with `block` (nil restores the real one) so tests don't
// depend on which apps are installed on the machine running them.
+ (void)setURLOpenabilityOverrideForTesting:(nullable BOOL (^)(NSURL *url))block;

@end

NS_ASSUME_NONNULL_END
