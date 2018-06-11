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
#import "iTermTextExtractor.h"
#import "iTermURLStore.h"
#import "iTermSemanticHistoryController.h"
#import "NSCharacterSet+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "RegexKitLite.h"
#import "SCPPath.h"
#import "SmartSelectionController.h"
#import "URLAction.h"
#import "VT100RemoteHost.h"

@implementation iTermURLActionFactory

+ (URLAction *)urlActionAtCoord:(VT100GridCoord)coord
            respectHardNewlines:(BOOL)respectHardNewlines
               workingDirectory:(NSString *)workingDirectory
                     remoteHost:(VT100RemoteHost *)remoteHost
                      selectors:(NSDictionary<NSNumber *, NSString *> *)selectors
                          rules:(NSArray *)rules
                      extractor:(iTermTextExtractor *)extractor
      semanticHistoryController:(iTermSemanticHistoryController *)semanticHistoryController
                    pathFactory:(SCPPath *(^)(NSString *, int))pathFactory {
    URLAction *action;
    action = [self urlActionForHypertextLinkAt:coord extractor:extractor];
    if (action) {
        return action;
    }

    NSMutableIndexSet *continuationCharsCoords = [NSMutableIndexSet indexSet];
    NSMutableArray *prefixCoords = [NSMutableArray array];
    NSString *prefix = [extractor wrappedStringAt:coord
                                          forward:NO
                              respectHardNewlines:respectHardNewlines
                                         maxChars:[iTermAdvancedSettingsModel maxSemanticHistoryPrefixOrSuffix]
                                continuationChars:continuationCharsCoords
                              convertNullsToSpace:NO
                                           coords:prefixCoords];

    NSMutableArray *suffixCoords = [NSMutableArray array];
    NSString *suffix = [extractor wrappedStringAt:coord
                                          forward:YES
                              respectHardNewlines:respectHardNewlines
                                         maxChars:[iTermAdvancedSettingsModel maxSemanticHistoryPrefixOrSuffix]
                                continuationChars:continuationCharsCoords
                              convertNullsToSpace:NO
                                           coords:suffixCoords];

    action = [self urlActionForExistingFileAt:coord
                                       prefix:prefix
                                 prefixCoords:prefixCoords
                                       suffix:suffix
                                 suffixCoords:suffixCoords
                             workingDirectory:workingDirectory
                                    extractor:extractor
                    semanticHistoryController:semanticHistoryController];
    if (action) {
        return action;
    }

    action = [self urlActionForSmartSelectionAt:coord
                            respectHardNewlines:respectHardNewlines
                               workingDirectory:workingDirectory
                                     remoteHost:remoteHost
                                          rules:rules
                                      selectors:selectors
                                  textExtractor:extractor];
    if (action) {
        return action;
    }

    action = [self urlActionForAnyStringSemanticHistoryAt:coord
                                         workingDirectory:workingDirectory
                                                    rules:rules
                                            textExtractor:extractor
                                semanticHistoryController:semanticHistoryController];
    if (action) {
        return action;
    }

    // No luck. Look for something vaguely URL-like.
    action = [self urlActionForURLAt:coord
                              prefix:prefix
                        prefixCoords:prefixCoords
                              suffix:suffix
                        suffixCoords:suffixCoords
                           extractor:extractor];
    if (action) {
        return action;
    }

    // TODO: We usually don't get here because "foo.txt" looks enough like a URL that we do a DNS
    // lookup and fail. It'd be nice to fallback to an SCP file path.
    // See if we can conjure up a secure copy path.
    return [self urlActionWithSecureCopyAt:coord
                                     rules:rules
                             textExtractor:extractor
                               pathFactory:pathFactory];
}

#pragma mark - Sub-factories

+ (URLAction *)urlActionForHypertextLinkAt:(VT100GridCoord)coord
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

+ (URLAction *)urlActionForExistingFileAt:(VT100GridCoord)coord
                                   prefix:(NSString *)prefix
                             prefixCoords:(NSArray *)prefixCoords
                                   suffix:(NSString *)suffix
                             suffixCoords:(NSArray *)suffixCoords
                         workingDirectory:(NSString *)workingDirectory
                                extractor:(iTermTextExtractor *)extractor
                semanticHistoryController:(iTermSemanticHistoryController *)semanticHistoryController {
    NSString *possibleFilePart1 =
        [prefix substringIncludingOffset:[prefix length] - 1
                        fromCharacterSet:[NSCharacterSet filenameCharacterSet]
                    charsTakenFromPrefix:NULL];
    NSString *possibleFilePart2 =
        [suffix substringIncludingOffset:0
                        fromCharacterSet:[NSCharacterSet filenameCharacterSet]
                    charsTakenFromPrefix:NULL];

    int prefixChars = 0;
    int suffixChars = 0;
    // First, try to locate an existing filename at this location.
    NSString *filename =
    [semanticHistoryController pathOfExistingFileFoundWithPrefix:possibleFilePart1
                                                          suffix:possibleFilePart2
                                                workingDirectory:workingDirectory
                                            charsTakenFromPrefix:&prefixChars
                                            charsTakenFromSuffix:&suffixChars
                                                  trimWhitespace:NO];

    // Don't consider / to be a valid filename because it's useless and single/double slashes are
    // pretty common.
    if (filename.length > 0 &&
        ![[filename stringByReplacingOccurrencesOfString:@"//" withString:@"/"] isEqualToString:@"/"]) {
        DLog(@"Accepting filename from brute force search: %@", filename);
        // If you clicked on an existing filename, use it.
        URLAction *action = [URLAction urlActionToOpenExistingFile:filename];
        VT100GridWindowedRange range;

        if (prefixCoords.count > 0 && prefixChars > 0) {
            NSInteger i = MAX(0, (NSInteger)prefixCoords.count - prefixChars);
            range.coordRange.start = [prefixCoords[i] gridCoordValue];
        } else {
            // Everything is coming from the suffix (e.g., when mouse is on first char of filename)
            range.coordRange.start = [suffixCoords[0] gridCoordValue];
        }
        VT100GridCoord lastCoord;
        // Ensure we don't run off the end of suffixCoords if something unexpected happens.
        // Subtract 1 because the 0th index into suffixCoords corresponds to 1 suffix char being used, etc.
        NSInteger i = MIN((NSInteger)suffixCoords.count - 1, suffixChars - 1);
        if (i >= 0) {
            lastCoord = [suffixCoords[i] gridCoordValue];
        } else {
            // This shouldn't happen, but better safe than sorry
            lastCoord = [[prefixCoords lastObject] gridCoordValue];
        }
        range.coordRange.end = [extractor successorOfCoord:lastCoord];
        range.columnWindow = extractor.logicalWindow;
        action.range = range;

        NSString *lineNumber = nil;
        NSString *columnNumber = nil;
        action.rawFilename = filename;
        action.fullPath = [semanticHistoryController cleanedUpPathFromPath:filename
                                                                    suffix:[suffix substringFromIndex:suffixChars]
                                                          workingDirectory:workingDirectory
                                                       extractedLineNumber:&lineNumber
                                                              columnNumber:&columnNumber];
        action.lineNumber = lineNumber;
        action.columnNumber = columnNumber;
        action.workingDirectory = workingDirectory;
        return action;
    }

    return nil;
}

+ (URLAction *)urlActionForSmartSelectionAt:(VT100GridCoord)coord
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
                                            ignoringNewlines:[iTermAdvancedSettingsModel ignoreHardNewlinesInURLs]];
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

+ (URLAction *)urlActionForAnyStringSemanticHistoryAt:(VT100GridCoord)coord
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
                                                ignoringNewlines:[iTermAdvancedSettingsModel ignoreHardNewlinesInURLs]];
        if (!VT100GridCoordEquals(smartRange.coordRange.start,
                                  smartRange.coordRange.end)) {
            NSString *name = smartMatch.components[0];
            URLAction *action = [URLAction urlActionToOpenExistingFile:name];
            action.range = smartRange;
            action.fullPath = name;
            action.workingDirectory = workingDirectory;
            return action;
        }
    }
    return nil;
}

+ (URLAction *)urlActionForURLAt:(VT100GridCoord)coord
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
            NSString *defaultScheme = @"http://";
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

+ (URLAction *)urlActionForString:(NSString *)stringWithoutNearbyPunctuation
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

+ (URLAction *)urlActionWithSecureCopyAt:(VT100GridCoord)coord
                                   rules:(NSArray *)rules
                           textExtractor:(iTermTextExtractor *)textExtractor
                             pathFactory:(SCPPath *(^)(NSString *, int))pathFactory {
    VT100GridWindowedRange smartRange;
    SmartMatch *smartMatch = [textExtractor smartSelectionAt:coord
                                                   withRules:rules
                                              actionRequired:NO
                                                       range:&smartRange
                                            ignoringNewlines:[iTermAdvancedSettingsModel ignoreHardNewlinesInURLs]];
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

+ (BOOL)stringLooksLikeURL:(NSString*)s {
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

@end

