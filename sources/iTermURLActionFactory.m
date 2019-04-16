//
//  iTermURLActionFactory.m
//  iTerm2
//
//  Created by George Nachman on 2/26/17.
//
//

#import "iTermURLActionFactory.h"

#import "ContextMenuActionPrefsController.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPathFinder.h"
#import "iTermSemanticHistoryController.h"
#import "iTermTextExtractor.h"
#import "iTermURLStore.h"
#import "NSCharacterSet+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "RegexKitLite.h"
#import "SCPPath.h"
#import "SmartSelectionController.h"
#import "URLAction.h"
#import "VT100RemoteHost.h"

static NSString *const iTermURLActionFactoryCancelPathfinders = @"iTermURLActionFactoryCancelPathfinders";

typedef enum {
    iTermURLActionFactoryPhaseHypertextLink,
    iTermURLActionFactoryPhaseExistingFile,
    iTermURLActionFactoryPhaseSmartSelectionAction,
    iTermURLActionFactoryPhaseAnyStringSemanticHistory,
    iTermURLActionFactoryPhaseURLLike,
    iTermURLActionFactoryPhaseSecureCopy,
    iTermURLActionFactoryPhaseFailed
} iTermURLActionFactoryPhase;

@interface iTermURLActionFactory()
@property (nonatomic) VT100GridCoord coord;
@property (nonatomic) BOOL respectHardNewlines;
@property (nonatomic, copy) NSString *workingDirectory;
@property (nonatomic, strong) VT100RemoteHost *remoteHost;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSString *> *selectors;
@property (nonatomic, copy) NSArray *rules;
@property (nonatomic, strong) iTermTextExtractor *extractor;
@property (nonatomic, strong) iTermSemanticHistoryController *semanticHistoryController;
@property (nonatomic, copy) SCPPath *(^pathFactory)(NSString *, int);
@property (nonatomic, copy) void (^completion)(URLAction *);
@property (nonatomic) iTermURLActionFactoryPhase phase;

@property (nonatomic, strong) NSMutableIndexSet *continuationCharsCoords;
@property (nonatomic, strong) NSMutableArray *prefixCoords;
@property (nonatomic, strong) NSString *prefix;
@property (nonatomic, strong) NSMutableArray *suffixCoords;
@property (nonatomic, strong) NSString *suffix;
@end

static NSMutableArray<iTermURLActionFactory *> *sFactories;

@implementation iTermURLActionFactory {
    BOOL _finished;
    iTermPathFinder *_pathfinder;
}

+ (void)urlActionAtCoord:(VT100GridCoord)coord
     respectHardNewlines:(BOOL)respectHardNewlines
        workingDirectory:(NSString *)workingDirectory
              remoteHost:(VT100RemoteHost *)remoteHost
               selectors:(NSDictionary<NSNumber *, NSString *> *)selectors
                   rules:(NSArray *)rules
               extractor:(iTermTextExtractor *)extractor
semanticHistoryController:(iTermSemanticHistoryController *)semanticHistoryController
             pathFactory:(SCPPath *(^)(NSString *, int))pathFactory
              completion:(void (^)(URLAction *))completion {
    iTermURLActionFactory *factory = [[iTermURLActionFactory alloc] init];
    factory.coord = coord;
    factory.respectHardNewlines = respectHardNewlines;
    factory.workingDirectory = workingDirectory;
    factory.remoteHost = remoteHost;
    factory.selectors = selectors;
    factory.rules = rules;
    factory.extractor = extractor;
    factory.semanticHistoryController = semanticHistoryController;
    factory.pathFactory = pathFactory;
    factory.completion = completion;
    factory.phase = iTermURLActionFactoryPhaseHypertextLink;
    [[NSNotificationCenter defaultCenter] addObserver:factory
                                             selector:@selector(cancelPathfinders:)
                                                 name:iTermURLActionFactoryCancelPathfinders
                                               object:nil];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sFactories = [NSMutableArray array];
    });

    [sFactories addObject:factory];
    [factory tryCurrentPhase];
}

// This is always eventually callsed.
- (void)completeWithAction:(URLAction *)action {
    _finished = YES;
    self.completion(action);
    [sFactories removeObject:self];
}

- (void)fail {
    self.phase = self.phase + 1;
    [self tryCurrentPhase];
}

- (void)tryCurrentPhase {
    switch (self.phase) {
        case iTermURLActionFactoryPhaseHypertextLink:
            [self tryHypertextLink];
            break;
        case iTermURLActionFactoryPhaseExistingFile:
            [self tryExistingFile];
            break;
        case iTermURLActionFactoryPhaseSmartSelectionAction:
            [self trySmartSelectionAction];
            break;
        case iTermURLActionFactoryPhaseAnyStringSemanticHistory:
            [self tryAnyStringSemanticHistory];
            break;
        case iTermURLActionFactoryPhaseURLLike:
            [self tryURLLike];
            break;
        case iTermURLActionFactoryPhaseSecureCopy:
            [self trySecureCopy];
            break;
        case iTermURLActionFactoryPhaseFailed:
            [self completeWithAction:nil];
            break;
    }
}

- (void)tryHypertextLink {
    URLAction *action;
    action = [self urlActionForHypertextLinkAt:self.coord
                                     extractor:self.extractor];
    if (action) {
        [self completeWithAction:action];
    } else {
        [self fail];
    }
}

- (void)tryExistingFile {
    self.continuationCharsCoords = [NSMutableIndexSet indexSet];
    self.prefixCoords = [NSMutableArray array];
    self.prefix = [self.extractor wrappedStringAt:self.coord
                                          forward:NO
                              respectHardNewlines:self.respectHardNewlines
                                         maxChars:[iTermAdvancedSettingsModel maxSemanticHistoryPrefixOrSuffix]
                                continuationChars:self.continuationCharsCoords
                              convertNullsToSpace:NO
                                           coords:self.prefixCoords];

    self.suffixCoords = [NSMutableArray array];
    self.suffix = [self.extractor wrappedStringAt:self.coord
                                          forward:YES
                              respectHardNewlines:self.respectHardNewlines
                                         maxChars:[iTermAdvancedSettingsModel maxSemanticHistoryPrefixOrSuffix]
                                continuationChars:self.continuationCharsCoords
                              convertNullsToSpace:NO
                                           coords:self.suffixCoords];

    [self urlActionForExistingFileAt:self.coord
                              prefix:self.prefix
                        prefixCoords:self.prefixCoords
                              suffix:self.suffix
                        suffixCoords:self.suffixCoords
                    workingDirectory:self.workingDirectory
                           extractor:self.extractor
           semanticHistoryController:self.semanticHistoryController
                          completion:^(URLAction *action) {
                              if (action) {
                                  [self completeWithAction:action];
                              } else {
                                  [self fail];
                              }
                          }];
}

- (void)trySmartSelectionAction {
    URLAction *action = [self urlActionForSmartSelectionAt:self.coord
                                       respectHardNewlines:self.respectHardNewlines
                                          workingDirectory:self.workingDirectory
                                                remoteHost:self.remoteHost
                                                     rules:self.rules
                                                 selectors:self.selectors
                                             textExtractor:self.extractor];
    if (action) {
        [self completeWithAction:action];
    } else {
        [self fail];
    }
}

- (void)tryAnyStringSemanticHistory {
    URLAction *action = [self urlActionForAnyStringSemanticHistoryAt:self.coord
                                                 respectHardNewlines:self.respectHardNewlines
                                                    workingDirectory:self.workingDirectory
                                                               rules:self.rules
                                                       textExtractor:self.extractor
                                           semanticHistoryController:self.semanticHistoryController];
    if (action) {
        [self completeWithAction:action];
    } else {
        [self fail];
    }
}

- (void)tryURLLike {
    // No luck. Look for something vaguely URL-like.
    URLAction *action = [self urlActionForURLAt:self.coord
                                         prefix:self.prefix
                                   prefixCoords:self.prefixCoords
                                         suffix:self.suffix
                                   suffixCoords:self.suffixCoords
                                      extractor:self.extractor];
    if (action) {
        [self completeWithAction:action];
    } else {
        [self fail];
    }
}

- (void)trySecureCopy {
    // TODO: We usually don't get here because "foo.txt" looks enough like a URL that we do a DNS
    // lookup and fail. It'd be nice to fallback to an SCP file path.
    // See if we can conjure up a secure copy path.
    URLAction *action = [self urlActionWithSecureCopyAt:self.coord
                                    respectHardNewlines:self.respectHardNewlines
                                                  rules:self.rules
                                          textExtractor:self.extractor
                                            pathFactory:self.pathFactory];
    if (action) {
        [self completeWithAction:action];
    } else {
        [self fail];
    }
}

#pragma mark - Sub-factories

- (URLAction *)urlActionForHypertextLinkAt:(VT100GridCoord)coord
                                 extractor:(iTermTextExtractor *)extractor {
    screen_char_t oc = [extractor characterAt:coord];
    NSString *urlId = nil;
    NSURL *url = [extractor urlOfHypertextLinkAt:coord urlId:&urlId];
    if (url != nil) {
        URLAction *action = [URLAction urlActionToOpenURL:url.absoluteString];
        action.hover = YES;
        action.range = [extractor rangeOfCoordinatesAround:coord
                                           maximumDistance:1000
                                               passingTest:^BOOL(screen_char_t *c, VT100GridCoord coord) {
                                                   if (c->urlCode == oc.urlCode) {
                                                       return YES;
                                                   }
                                                   NSString *thisId;
                                                   NSURL *thisURL = [extractor urlOfHypertextLinkAt:coord urlId:&thisId];
                                                   // Hover together only if URL and ID are equal.
                                                   return ([thisURL isEqual:url] && (thisId == urlId || [thisId isEqualToString:urlId]));
                                               }];
        return action;
    } else {
        return nil;
    }
}

- (void)urlActionForExistingFileAt:(VT100GridCoord)coord
                            prefix:(NSString *)prefix
                      prefixCoords:(NSArray *)prefixCoords
                            suffix:(NSString *)suffix
                      suffixCoords:(NSArray *)suffixCoords
                  workingDirectory:(NSString *)workingDirectory
                         extractor:(iTermTextExtractor *)extractor
         semanticHistoryController:(iTermSemanticHistoryController *)semanticHistoryController
                        completion:(void (^)(URLAction *))completion {
    NSString *possibleFilePart1 =
        [prefix substringIncludingOffset:[prefix length] - 1
                        fromCharacterSet:[NSCharacterSet filenameCharacterSet]
                    charsTakenFromPrefix:NULL];
    NSString *possibleFilePart2 =
        [suffix substringIncludingOffset:0
                        fromCharacterSet:[NSCharacterSet filenameCharacterSet]
                    charsTakenFromPrefix:NULL];

#warning TOOD: Don't just cancel them. If one's already running with the same inputs, glom on to it. Also, don't re-do the work when the user clicks. Furthermore, abort when the command key is released.
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermURLActionFactoryCancelPathfinders
                                                        object:nil];

    _pathfinder = [semanticHistoryController pathOfExistingFileFoundWithPrefix:possibleFilePart1
                                                                        suffix:possibleFilePart2
                                                              workingDirectory:workingDirectory
                                                                trimWhitespace:NO
                                                                    completion:^(NSString *filename, int prefixChars, int suffixChars) {
                                                                        URLAction *action = [self urlActionForFilename:filename
                                                                                                           prefixChars:prefixChars
                                                                                                           suffixChars:suffixChars];
                                                                        completion(action);
                                                                    }];
}

- (URLAction *)urlActionForFilename:(NSString *)filename
                        prefixChars:(int)prefixChars
                        suffixChars:(int)suffixChars {
    // Don't consider / to be a valid filename because it's useless and single/double slashes are
    // pretty common.
    if (filename.length == 0 ||
        [[filename stringByReplacingOccurrencesOfString:@"//" withString:@"/"] isEqualToString:@"/"]) {
        return nil;
    }

    DLog(@"Accepting filename from brute force search: %@", filename);
    // If you clicked on an existing filename, use it.
    URLAction *action = [URLAction urlActionToOpenExistingFile:filename];
    VT100GridWindowedRange range;

    if (self.prefixCoords.count > 0 && prefixChars > 0) {
        NSInteger i = MAX(0, (NSInteger)self.prefixCoords.count - prefixChars);
        range.coordRange.start = [self.prefixCoords[i] gridCoordValue];
    } else {
        // Everything is coming from the suffix (e.g., when mouse is on first char of filename)
        range.coordRange.start = [self.suffixCoords[0] gridCoordValue];
    }
    VT100GridCoord lastCoord;
    // Ensure we don't run off the end of suffixCoords if something unexpected happens.
    // Subtract 1 because the 0th index into suffixCoords corresponds to 1 suffix char being used, etc.
    NSInteger i = MIN((NSInteger)self.suffixCoords.count - 1, suffixChars - 1);
    if (i >= 0) {
        lastCoord = [self.suffixCoords[i] gridCoordValue];
    } else {
        // This shouldn't happen, but better safe than sorry
        lastCoord = [[self.prefixCoords lastObject] gridCoordValue];
    }
    range.coordRange.end = [self.extractor successorOfCoord:lastCoord];
    range.columnWindow = self.extractor.logicalWindow;
    action.range = range;

    NSString *lineNumber = nil;
    NSString *columnNumber = nil;
    action.rawFilename = filename;
    action.fullPath = [self.semanticHistoryController cleanedUpPathFromPath:filename
                                                                     suffix:[self.suffix substringFromIndex:suffixChars]
                                                           workingDirectory:self.workingDirectory
                                                        extractedLineNumber:&lineNumber
                                                               columnNumber:&columnNumber];
    action.lineNumber = lineNumber;
    action.columnNumber = columnNumber;
    action.workingDirectory = self.workingDirectory;
    return action;
}

- (URLAction *)urlActionForSmartSelectionAt:(VT100GridCoord)coord
                        respectHardNewlines:(BOOL)respectHardNewlines
                           workingDirectory:(NSString *)workingDirectory
                                 remoteHost:(VT100RemoteHost *)remoteHost
                                      rules:(NSArray *)rules
                                  selectors:(NSDictionary<NSNumber *, NSString *> *)selectors
                              textExtractor:(iTermTextExtractor *)textExtractor {
    // Next, see if smart selection matches anything with an action.
    VT100GridWindowedRange smartRange;
    SmartMatch *smartMatch = [textExtractor smartSelectionAt:coord
                                                   withRules:rules
                                              actionRequired:YES
                                                       range:&smartRange
                                            ignoringNewlines:!respectHardNewlines];
    NSArray *actions = [SmartSelectionController actionsInRule:smartMatch.rule];
    DLog(@"  Smart selection produces these actions: %@", actions);
    if (actions.count) {
        NSString *content = smartMatch.components[0];
        if (!respectHardNewlines) {
            content = [content stringByReplacingOccurrencesOfString:@"\n" withString:@""];
        }
        DLog(@"  Actions match this content: %@", content);
        URLAction *action = [URLAction urlActionToPerformSmartSelectionRule:smartMatch.rule
                                                                   onString:content];
        action.range = smartRange;
        ContextMenuActions value = [ContextMenuActionPrefsController actionForActionDict:actions[0]];
        action.selector = NSSelectorFromString(selectors[@(value)]);
        action.representedObject = [ContextMenuActionPrefsController parameterForActionDict:actions[0]
                                                                      withCaptureComponents:smartMatch.components
                                                                           workingDirectory:workingDirectory
                                                                                 remoteHost:remoteHost];
        return action;
    }
    return nil;
}

- (URLAction *)urlActionForAnyStringSemanticHistoryAt:(VT100GridCoord)coord
                                  respectHardNewlines:(BOOL)respectHardNewlines
                                     workingDirectory:(NSString *)workingDirectory
                                                rules:(NSArray *)rules
                                        textExtractor:(iTermTextExtractor *)textExtractor
                            semanticHistoryController:(iTermSemanticHistoryController *)semanticHistoryController {
    if (semanticHistoryController.activatesOnAnyString) {
        // Just do smart selection and let Semantic History take it.
        VT100GridWindowedRange smartRange;
        SmartMatch *smartMatch = [textExtractor smartSelectionAt:coord
                                                       withRules:rules
                                                  actionRequired:NO
                                                           range:&smartRange
                                                ignoringNewlines:!respectHardNewlines];
        if (!VT100GridCoordEquals(smartRange.coordRange.start,
                                  smartRange.coordRange.end)) {
            NSString *name = smartMatch.components[0];
            URLAction *action = [URLAction urlActionToOpenExistingFile:name];
            action.rawFilename = name;
            action.range = smartRange;
            action.fullPath = name;
            action.workingDirectory = workingDirectory;
            return action;
        }
    }
    return nil;
}

- (URLAction *)urlActionForURLAt:(VT100GridCoord)coord
                          prefix:(NSString *)prefix
                    prefixCoords:(NSArray *)prefixCoords
                          suffix:(NSString *)suffix
                    suffixCoords:(NSArray *)suffixCoords
                       extractor:(iTermTextExtractor *)extractor {
    NSString *joined = [prefix stringByAppendingString:suffix];
    DLog(@"Smart selection found nothing. Look for URL-like things in %@ around offset %d",
         joined, (int)[prefix length]);
    int prefixChars = 0;
    NSString *possibleUrl = [joined substringIncludingOffset:[prefix length]
                                            fromCharacterSet:[NSCharacterSet urlCharacterSet]
                                        charsTakenFromPrefix:&prefixChars];
    DLog(@"String of just permissible chars is %@", possibleUrl);

    // Remove punctuation, parens, brackets, etc.
    NSRange rangeWithoutNearbyPunctuation = [possibleUrl rangeOfURLInString];
    if (rangeWithoutNearbyPunctuation.location == NSNotFound) {
        DLog(@"No URL found");
        return nil;
    }
    prefixChars -= rangeWithoutNearbyPunctuation.location;
    NSString *stringWithoutNearbyPunctuation = [possibleUrl substringWithRange:rangeWithoutNearbyPunctuation];
    DLog(@"String without nearby punctuation: %@", stringWithoutNearbyPunctuation);

    if ([iTermAdvancedSettingsModel conservativeURLGuessing]) {
        if (![self stringLooksLikeURL:stringWithoutNearbyPunctuation]) {
            return nil;
        }

        NSString *schemeRegex = @"^[a-z]+://";
        // Hostname with two components
        NSString *hostnameRegex = @"(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)+([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])";
        NSString *pathRegex = @"/";
        NSString *urlRegex = [NSString stringWithFormat:@"%@%@%@", schemeRegex, hostnameRegex, pathRegex];
        if ([stringWithoutNearbyPunctuation rangeOfRegex:urlRegex].location != NSNotFound) {
            return [self urlActionForString:stringWithoutNearbyPunctuation
                                      range:rangeWithoutNearbyPunctuation
                                     prefix:prefix
                               prefixCoords:prefixCoords
                                prefixChars:prefixChars
                               suffixCoords:suffixCoords
                                  extractor:extractor];
        }

        return nil;
    }

    const BOOL hasColon = ([stringWithoutNearbyPunctuation rangeOfString:@":"].location != NSNotFound);
    BOOL looksLikeURL;
    if (hasColon) {
        // The test later on for whether an app exists to open the URL is sufficient.
        DLog(@"Contains a colon so it looks like a URL to me");
        looksLikeURL = YES;
    } else {
        // Only try to use HTTP if the string has something especially HTTP URL-like about it, such as
        // containing a slash. This helps reduce the number of random strings that are misinterpreted
        // as URLs.
        looksLikeURL = [self stringLooksLikeURL:[possibleUrl substringWithRange:rangeWithoutNearbyPunctuation]];

        if (looksLikeURL) {
            DLog(@"There's no colon but it seems like it could be an HTTP URL. Let's give that a try.");
            NSString *defaultScheme = [[iTermAdvancedSettingsModel defaultURLScheme] stringByAppendingString:@":"];
            stringWithoutNearbyPunctuation = [defaultScheme stringByAppendingString:stringWithoutNearbyPunctuation];
        } else {
            DLog(@"Doesn't look enough like a URL to guess that it's an HTTP URL");
        }
    }

    if (looksLikeURL) {
        // If the string contains non-ascii characters, percent escape them. URLs are limited to ASCII.
        return [self urlActionForString:stringWithoutNearbyPunctuation
                                  range:rangeWithoutNearbyPunctuation
                                 prefix:prefix
                           prefixCoords:prefixCoords
                            prefixChars:prefixChars
                           suffixCoords:suffixCoords
                              extractor:extractor];
    }

    return nil;
}

- (URLAction *)urlActionForString:(NSString *)stringWithoutNearbyPunctuation
                            range:(NSRange)rangeWithoutNearbyPunctuation
                           prefix:(NSString *)prefix
                     prefixCoords:(NSArray *)prefixCoords
                      prefixChars:(int)prefixChars
                     suffixCoords:(NSArray *)suffixCoords
                        extractor:(iTermTextExtractor *)extractor {
    NSURL *url = [NSURL URLWithUserSuppliedString:stringWithoutNearbyPunctuation];
    // If something can handle the scheme then we're all set.
    BOOL openable = (url &&
                     [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:url] != nil &&
                     prefixChars >= 0 &&
                     prefixChars <= prefix.length);

    if (openable) {
        DLog(@"%@ is openable", url);
        VT100GridWindowedRange range;
        NSInteger j = prefix.length - prefixChars;
        if (j < prefixCoords.count) {
            range.coordRange.start = [prefixCoords[j] gridCoordValue];
        } else if (j == prefixCoords.count && j > 0) {
            range.coordRange.start = [extractor successorOfCoord:[prefixCoords[j - 1] gridCoordValue]];
        } else {
            DLog(@"prefixCoordscount=%@ j=%@", @(prefixCoords.count), @(j));
            return nil;
        }
        NSInteger i = rangeWithoutNearbyPunctuation.length - prefixChars;
        if (i < suffixCoords.count) {
            range.coordRange.end = [suffixCoords[i] gridCoordValue];
        } else if (i > 0 && i == suffixCoords.count) {
            range.coordRange.end = [extractor successorOfCoord:[suffixCoords[i - 1] gridCoordValue]];
        } else {
            DLog(@"i=%@ suffixcoords.count=%@", @(i), @(suffixCoords.count));
            return nil;
        }
        range.columnWindow = extractor.logicalWindow;
        URLAction *action = [URLAction urlActionToOpenURL:stringWithoutNearbyPunctuation];
        action.range = range;
        return action;
    } else {
        DLog(@"%@ is not openable (couldn't convert it to a URL [%@] or no scheme handler",
             stringWithoutNearbyPunctuation, url);
    }
    return nil;
}

- (URLAction *)urlActionWithSecureCopyAt:(VT100GridCoord)coord
                     respectHardNewlines:(BOOL)respectHardNewlines
                                   rules:(NSArray *)rules
                           textExtractor:(iTermTextExtractor *)textExtractor
                             pathFactory:(SCPPath *(^)(NSString *, int))pathFactory {
    VT100GridWindowedRange smartRange;
    SmartMatch *smartMatch = [textExtractor smartSelectionAt:coord
                                                   withRules:rules
                                              actionRequired:NO
                                                       range:&smartRange
                                            ignoringNewlines:!respectHardNewlines];
    if (smartMatch) {
        SCPPath *scpPath = pathFactory([smartMatch.components firstObject], coord.y);
        if (scpPath) {
            URLAction *action = [URLAction urlActionToSecureCopyFile:scpPath];
            action.range = smartRange;
            return action;
        }
    }

    return nil;
}

#pragma mark - Helpers

- (BOOL)stringLooksLikeURL:(NSString*)s {
    // This is much harder than it sounds.
    // [NSURL URLWithString] is supposed to do this, but it doesn't accept IDN-encoded domains like
    // http://例子.测试
    // Just about any word can be a URL in the local search path. The code that calls this prefers false
    // positives, so just make sure it's not empty and doesn't have illegal characters.
    if ([s rangeOfCharacterFromSet:[[NSCharacterSet urlCharacterSet] invertedSet]].location != NSNotFound) {
        return NO;
    }
    if ([s length] == 0) {
        return NO;
    }

    NSRange slashRange = [s rangeOfString:@"/"];
    if (slashRange.location == 0) {
        // URLs never start with a slash
        return NO;
    }
    if (slashRange.length > 0) {
        // Contains a slash but does not start with it.
        return YES;
    }

    NSString *ipRegex = @"^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$";
    if ([s rangeOfRegex:ipRegex].location != NSNotFound) {
        // IP addresses as dotted quad
        return YES;
    }

    NSString *hostnameRegex = @"^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)+([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\\-]*[A-Za-z0-9])$";
    if ([s rangeOfRegex:hostnameRegex].location != NSNotFound) {
        // A hostname with at least two components.
        return YES;
    }

    return NO;
}

#pragma mark - Notifications

- (void)cancelPathfinders:(NSNotification *)notification {
    [_pathfinder cancel];
}

@end

