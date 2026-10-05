//
//  iTermURLActionFactory.h
//  iTerm2
//
//  Created by George Nachman on 2/26/17.
//
//

#import <Foundation/Foundation.h>

#import "VT100GridTypes.h"
#import "iTermCancelable.h"

@class iTermTextExtractor;
@protocol iTermObject;
@class iTermSemanticHistoryController;
@class iTermVariableScope;
@class SCPPath;
@class URLAction;
@protocol VT100RemoteHostReading;

@interface iTermURLActionFactory : NSObject<iTermCancelable>

+ (instancetype)urlActionAtCoord:(VT100GridCoord)coord
             respectHardNewlines:(BOOL)respectHardNewlines
                       alternate:(BOOL)alternate
                workingDirectory:(NSString *)workingDirectory
                           scope:(iTermVariableScope *)scope
                           owner:(id<iTermObject>)owner
                      remoteHost:(id<VT100RemoteHostReading>)remoteHost
                       selectors:(NSDictionary<NSNumber *, NSString *> *)selectors
                           rules:(NSArray *)rules
                       extractor:(iTermTextExtractor *)extractor
       semanticHistoryController:(iTermSemanticHistoryController *)semanticHistoryController
                     pathFactory:(SCPPath *(^)(NSString *, int))pathFactory
                      completion:(void (^)(URLAction *))completion;

// Synchronously returns the openable URL at `coord` (with hard newlines stripped
// from wrapped URLs when respectHardNewlines is NO), or nil if the text there does
// not carry a URL scheme the OS can open. This is the URL-detection portion of the
// ⌘-click machinery without the asynchronous filesystem/Semantic History probing, so
// it is suitable for populating a context menu synchronously.
// Returns nil if the text at `coord` does not carry a URL scheme the OS can open.
+ (NSURL *)openableURLAtCoord:(VT100GridCoord)coord
          respectHardNewlines:(BOOL)respectHardNewlines
                    extractor:(iTermTextExtractor *)extractor;

// Turns user-selected text (e.g. from “Open Selection as URL”) into a URL that
// -[iTermURLActionHelper openURL:...] can open, or nil. Surrounding punctuation is
// trimmed the way ⌘-click trims it. Text with an explicit scheme (scheme://...) is
// used as is. Otherwise, when guessScheme is YES and the text looks like a web
// address (a dotted hostname, IP address, or localhost, with an optional port and
// path), the default scheme ⌘-click would guess is applied: http for a single-word
// host, the defaultURLScheme advanced setting otherwise. That guess is preferred
// over reading the text before a colon as a scheme, so localhost:8080/foo is a web
// URL while mailto:alice still is not. Unlike ⌘-click the text has not been checked
// against the filesystem, so sources/Foo.m does not become a web URL. Like ⌘-click,
// no guessing happens when the conservativeURLGuessing advanced setting is on.
// Returning nil lets callers hide or skip the action rather than hand the OS a URL
// it will reject. Issue 13092.
+ (NSURL *)urlForUserSuppliedString:(NSString *)string guessingScheme:(BOOL)guessScheme;

@end
