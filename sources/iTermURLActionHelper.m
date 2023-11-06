//
//  iTermURLActionHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import "iTermURLActionHelper.h"

#import "DebugLogging.h"
#import "FileTransferManager.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermImageInfo.h"
#import "iTermLaunchServices.h"
#import "iTermSelection.h"
#import "iTermSemanticHistoryController.h"
#import "iTermTextExtractor.h"
#import "iTermURLActionFactory.h"
#import "iTermUserDefaults.h"
#import "NSEvent+iTerm.h"
#import "NSHost+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSURL+iTerm.h"
#import "SCPPath.h"
#import "SmartMatch.h"
#import "URLAction.h"

@implementation iTermURLActionHelper {
    NSInteger _openTargetGeneration;
}

- (instancetype)initWithSemanticHistoryController:(iTermSemanticHistoryController *)semanticHistoryController {
    self = [super init];
    if (self) {
        _semanticHistoryController = semanticHistoryController;
    }
    return self;
}

#pragma mark - APIs

- (BOOL)ignoreHardNewlinesInURLs {
    if ([iTermAdvancedSettingsModel ignoreHardNewlinesInURLs]) {
        return YES;
    }
    return [self.delegate urlActionHelperShouldIgnoreHardNewlines:self];
}

- (id<iTermCancelable>)urlActionForClickAtCoord:(VT100GridCoord)coord
                                     completion:(void (^)(URLAction *))completion {
    return [self urlActionForClickAtCoord:coord
                   respectingHardNewlines:![self ignoreHardNewlinesInURLs]
                                alternate:NO
                               completion:completion];
}

- (id<iTermCancelable>)urlActionForClickAtCoord:(VT100GridCoord)coord
                         respectingHardNewlines:(BOOL)respectHardNewlines
                                      alternate:(BOOL)alternate
                                     completion:(void (^)(URLAction *))completion {
    DLog(@"urlActionForClickAt:%@ respectingHardNewlines:%@",
         VT100GridCoordDescription(coord), @(respectHardNewlines));
    if (coord.y < 0) {
        completion(nil);
        return nil;
    }
    id<iTermImageInfoReading> imageInfo = [self.delegate urlActionHelper:self imageInfoAt:coord];
    if (imageInfo) {
        completion([URLAction urlActionToOpenImage:imageInfo]);
        return nil;
    }
    iTermTextExtractor *extractor = [self.delegate urlActionHelperNewTextExtractor:self];
    if ([extractor characterAt:coord].code == 0) {
        completion(nil);
        return nil;
    }
    [extractor restrictToLogicalWindowIncludingCoord:coord];

    __block id<iTermCancelable> urlActionFactoryCanceler = nil;
    iTermBlockCanceller *canceller = [[iTermBlockCanceller alloc] initWithBlock:^{
        [urlActionFactoryCanceler cancelOperation];
    }];
    [self.delegate urlActionHelper:self
            workingDirectoryOnLine:coord.y
                        completion:^(NSString *workingDirectory) {
        urlActionFactoryCanceler =
        [iTermURLActionFactory urlActionAtCoord:coord
                            respectHardNewlines:respectHardNewlines
                                      alternate:alternate
                               workingDirectory:workingDirectory ?: @""
                                          scope:[self.delegate urlActionHelperScope:self]
                                          owner:[self.delegate urlActionHelperOwner:self]
                                     remoteHost:[self.delegate urlActionHelper:self remoteHostOnLine:coord.y]
                                      selectors:[self.delegate urlActionHelperSmartSelectionActionSelectorDictionary:self]
                                          rules:[self.delegate urlActionHelperSmartSelectionRules:self]
                                      extractor:extractor
                      semanticHistoryController:self.semanticHistoryController
                                    pathFactory:^SCPPath *(NSString *path, int line) {
                                        return [self.delegate urlActionHelper:self secureCopyPathForFile:path onLine:line];
                                    }
                                     completion:completion];
    }];
    return canceller;
}

- (void)openTargetWithEvent:(NSEvent *)event inBackground:(BOOL)openInBackground {
    // Command click in place.
    const VT100GridCoord coord = [self.delegate urlActionHelper:self coordForEvent:event allowRightMarginOverflow:NO];
    __weak __typeof(self) weakSelf = self;
    const NSInteger generation = ++_openTargetGeneration;
    DLog(@"Look up URL action for coord %@, generation %@", VT100GridCoordDescription(coord), @(generation));
    // I tried respecting hard newlines if that is a legal URL, but that's such a broad definition
    // that it doesn't work well. Hard EOLs mid-url are very common. Let's try always ignoring them.
    [self urlActionForClickAtCoord:coord
            respectingHardNewlines:![self ignoreHardNewlinesInURLs]
                         alternate:!!(event.it_modifierFlags & NSEventModifierFlagOption)
                        completion:^(URLAction *action) {
                            [weakSelf finishOpeningTargetWithEvent:event
                                                             coord:coord
                                                      inBackground:openInBackground
                                                            action:action
                                                        generation:generation];
                        }];
}

- (void)findUrlInString:(NSString *)aURLString andOpenInBackground:(BOOL)background {
    DLog(@"findUrlInString:%@", aURLString);
    NSRange range = [aURLString rangeOfURLInString];
    if (range.location == NSNotFound) {
        DLog(@"No URL found");
        return;
    }
    NSString *trimmedURLString = [aURLString substringWithRange:range];
    if (!trimmedURLString) {
        DLog(@"string is empty");
        return;
    }
    NSURL *url = [NSURL URLWithUserSuppliedString:trimmedURLString];
    [self openURL:url inBackground:background workingDirectory:nil];
}

- (void)downloadFileAtSecureCopyPath:(SCPPath *)scpPath
                         displayName:(NSString *)name
                      locationInView:(VT100GridCoordRange)range {
    [self.delegate urlActionHelper:self startSecureCopyDownload:scpPath];

    NSDictionary *attributes = [self.delegate urlActionHelperAttributes:self];
    NSSize size = [name sizeWithAttributes:attributes];
    size.width = MAX(1, size.width);
    size.height = MAX(1, size.height);
    size.height = [self.delegate urlActionHelperLineHeight:self];
    NSImage *const image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [name drawAtPoint:NSMakePoint(0, 0) withAttributes:attributes];
    [image unlockFocus];

    NSPoint point = [self.delegate urlActionHelper:self pointForCoord:range.start];
    [[FileTransferManager sharedInstance] animateImage:image
                            intoDownloadsMenuFromPoint:point
                                              onScreen:[self.delegate urlActionHelperScreen:self]];
}

- (SmartMatch *)smartSelectAtAbsoluteCoord:(VT100GridAbsCoord)absCoord
                                        to:(VT100GridAbsWindowedRange *)rangePtr
                          ignoringNewlines:(BOOL)ignoringNewlines
                            actionRequired:(BOOL)actionRequired
                           respectDividers:(BOOL)respectDividers {
    const long long totalScrollbackOverflow = [self.delegate urlActionTotalScrollbackOverflow:self];
    BOOL ok;
    const VT100GridCoord coord = VT100GridCoordFromAbsCoord(absCoord,
                                                            totalScrollbackOverflow,
                                                            &ok);
    if (!ok) {
        *rangePtr = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0,
                                                                             totalScrollbackOverflow,
                                                                             0,
                                                                             totalScrollbackOverflow),
                                                  -1, -1);
        return nil;
    }
    iTermTextExtractor *extractor = [self.delegate urlActionHelperNewTextExtractor:self];
    if (respectDividers) {
        [extractor restrictToLogicalWindowIncludingCoord:coord];
    }
    VT100GridWindowedRange relativeRange;
    SmartMatch *result = [extractor smartSelectionAt:coord
                                           withRules:[self.delegate urlActionHelperSmartSelectionRules:self]
                                      actionRequired:actionRequired
                                               range:&relativeRange
                                    ignoringNewlines:ignoringNewlines];
    if (result) {
        *rangePtr = VT100GridAbsWindowedRangeFromWindowedRange(relativeRange,
                                                               totalScrollbackOverflow);
    } else {
        *rangePtr = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), -1, -1);
    }
    return result;
}

- (void)openSemanticHistoryPath:(NSString *)path
                  orRawFilename:(NSString *)rawFileName
                       fragment:(NSString *)fragment
               workingDirectory:(NSString *)workingDirectory
                     lineNumber:(NSString *)lineNumber
                   columnNumber:(NSString *)columnNumber
                         prefix:(NSString *)prefix
                         suffix:(NSString *)suffix
                     completion:(void (^)(BOOL ok))completion {
    NSDictionary *subs = [self semanticHistorySubstitutionsWithPrefix:prefix
                                                               suffix:suffix
                                                                 path:path
                                                     workingDirectory:workingDirectory
                                                           lineNumber:lineNumber
                                                         columnNumber:columnNumber];
    [self.semanticHistoryController openPath:path
                               orRawFilename:rawFileName
                                    fragment:fragment
                               substitutions:subs
                                       scope:[self.delegate urlActionHelperScope:self]
                                  lineNumber:lineNumber
                                columnNumber:columnNumber
                                  completion:completion];
}

- (void)smartSelectAndMaybeCopyWithEvent:(NSEvent *)event
                        ignoringNewlines:(BOOL)ignoringNewlines {
    const VT100GridAbsCoord coord = [self.delegate urlActionHelper:self absCoordForEvent:event allowRightMarginOverflow:NO];

    [self smartSelectAtAbsoluteCoord:coord ignoringNewlines:ignoringNewlines];
    [self.delegate urlActionHelperCopySelectionIfNeeded:self];
}

#pragma mark - Open Target

// If iTerm2 is the handler for the scheme, then the profile is launched directly.
// Otherwise it's passed to the OS to launch.
- (void)openURL:(NSURL *)url inBackground:(BOOL)background workingDirectory:(NSString *)workingDirectory {
    DLog(@"openURL:%@ inBackground:%@", url, @(background));

    Profile *profile = [[iTermLaunchServices sharedInstance] profileForScheme:[url scheme]];
    if (profile) {
        [self.delegate urlActionHelper:self launchProfileInCurrentTerminal:profile withURL:url];
        return;
    }
    if ([url.scheme isEqualToString:@"file"] && url.fragment) {
        NSArray<NSString *> *parts = [url.fragment componentsSeparatedByString:@":"];
        NSString *lineNumber = (parts.count > 0) ? parts[0] : nil;
        NSString *columnNumber = (parts.count > 1) ? parts[1] : nil;
        NSDictionary *subs = [self semanticHistorySubstitutionsWithPrefix:@""
                                                                   suffix:url.path
                                                                     path:url.path
                                                         workingDirectory:workingDirectory
                                                               lineNumber:lineNumber.isNumeric ? lineNumber : nil
                                                             columnNumber:columnNumber.isNumeric && lineNumber.isNumeric ? columnNumber : nil];
        [self.semanticHistoryController openPath:url.path
                                   orRawFilename:url.path
                                        fragment:url.fragment
                                   substitutions:subs
                                           scope:[self.delegate urlActionHelperScope:self]
                                      lineNumber:lineNumber
                                    columnNumber:columnNumber
                                      completion:^(BOOL ignore) {}];
        return;
    }
    if (background) {
        [[NSWorkspace sharedWorkspace] openURLs:@[ url ]
                        withAppBundleIdentifier:nil
                                        options:NSWorkspaceLaunchWithoutActivation
                 additionalEventParamDescriptor:nil
                              launchIdentifiers:nil];
    } else {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (void)finishOpeningTargetWithEvent:(NSEvent *)event
                               coord:(VT100GridCoord)coord
                        inBackground:(BOOL)openInBackground
                              action:(URLAction *)action
                          generation:(NSInteger)generation {
    if (generation != _openTargetGeneration) {
        DLog(@"Canceled open target for generation %@", @(generation));
        return;
    }

    iTermTextExtractor *extractor = [self.delegate urlActionHelperNewTextExtractor:self];
    if ([iTermAdvancedSettingsModel restrictSemanticHistoryPrefixAndSuffixToLogicalWindow]) {
        [extractor restrictToLogicalWindowIncludingCoord:coord];
    }

    DLog(@"openTargetWithEvent generation %@ has action=%@", @(generation), action);
    if (action) {
        switch (action.actionType) {
            case kURLActionOpenExistingFile: {
                iTermLocatedString *locatedPrefix = [extractor wrappedLocatedStringAt:coord
                                                                              forward:NO
                                                                  respectHardNewlines:![self ignoreHardNewlinesInURLs]
                                                                             maxChars:[iTermAdvancedSettingsModel maxSemanticHistoryPrefixOrSuffix]
                                                                    continuationChars:nil
                                                                  convertNullsToSpace:YES];
                NSString *extendedPrefix = locatedPrefix.string;

                iTermLocatedString *locatedSuffix = [extractor wrappedLocatedStringAt:coord
                                                                              forward:YES
                                                                  respectHardNewlines:![self ignoreHardNewlinesInURLs]
                                                                             maxChars:[iTermAdvancedSettingsModel maxSemanticHistoryPrefixOrSuffix]
                                                                    continuationChars:nil
                                                                  convertNullsToSpace:YES];
                NSString *extendedSuffix = locatedSuffix.string;

                __weak __typeof(self) weakSelf = self;
                [self openSemanticHistoryPath:action.fullPath
                                orRawFilename:action.rawFilename
                                     fragment:nil
                             workingDirectory:action.workingDirectory
                                   lineNumber:action.lineNumber
                                 columnNumber:action.columnNumber
                                       prefix:extendedPrefix
                                       suffix:extendedSuffix
                                   completion:^(BOOL ok) {
                                       if (!ok) {
                                           [weakSelf findUrlInString:action.string
                                                 andOpenInBackground:openInBackground];
                                       }
                                   }];
                break;
            }
            case kURLActionOpenURL: {
                NSURL *url = [NSURL URLWithUserSuppliedString:action.string];
                if ([url.scheme isEqualToString:@"file"] &&
                    url.host.length > 0 &&
                    url.path.length > 0 &&
                    ![url.host isEqualToString:[NSHost fullyQualifiedDomainName]]) {
                    SCPPath *path = [[SCPPath alloc] init];
                    path.path = url.path;
                    path.hostname = url.host;
                    path.username = [self.class usernameToDownloadFileOnHost:url.host];
                    if (path.username == nil) {
                        return;
                    }
                    [self downloadFileAtSecureCopyPath:path
                                           displayName:url.path.lastPathComponent
                                        locationInView:action.range.coordRange];
                } else {
                    [self openURL:url inBackground:openInBackground workingDirectory:action.workingDirectory];
                }
                break;
            }

            case kURLActionSmartSelectionAction: {
                DLog(@"Run smart selection selector %@", NSStringFromSelector(action.selector));
                [self.smartSelectionActionTarget it_performNonObjectReturningSelector:action.selector
                                                                           withObject:action];
                break;
            }

            case kURLActionOpenImage:
                DLog(@"Open image");
                [[NSWorkspace sharedWorkspace] openFile:[(id<iTermImageInfoReading>)action.identifier nameForNewSavedTempFile]];
                break;

            case kURLActionSecureCopyFile:
                DLog(@"Secure copy file.");
                [self downloadFileAtSecureCopyPath:action.identifier
                                       displayName:action.string
                                    locationInView:action.range.coordRange];
                break;

            case kURLActionShowCommandInfo:
                [self.delegate urlActionHelperShowCommandInfoForMark:action.mark
                                                               coord:action.coord];
                break;
        }
    }
}

#pragma mark - Semantic History

- (NSDictionary *)semanticHistorySubstitutionsWithPrefix:(NSString *)prefix
                                                  suffix:(NSString *)suffix
                                                    path:(NSString *)path
                                        workingDirectory:(NSString *)workingDirectory
                                              lineNumber:(NSString *)lineNumber
                                            columnNumber:(NSString *)columnNumber {
    return
    @{ kSemanticHistoryPrefixSubstitutionKey: [prefix stringEscapedForBash] ?: @"",
       kSemanticHistorySuffixSubstitutionKey: [suffix stringEscapedForBash] ?: @"",
       kSemanticHistoryPathSubstitutionKey: [path stringEscapedForBash] ?: @"",
       kSemanticHistoryWorkingDirectorySubstitutionKey: [workingDirectory stringEscapedForBash] ?: @"",
       kSemanticHistoryLineNumberKey: lineNumber ?: @"",
       kSemanticHistoryColumnNumberKey: columnNumber ?: @""
       };
}

#pragma mark - Secure Copy

+ (NSString *)usernameToDownloadFileOnHost:(NSString *)host {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Enter username for host %@ to download file with scp", host];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [input setStringValue:NSUserName()];
    [alert setAccessoryView:input];
    [alert layout];
    [[alert window] makeFirstResponder:input];
    NSInteger button = [alert runModal];
    if (button == NSAlertFirstButtonReturn) {
        [input validateEditing];
        return [[input stringValue] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    }
    return nil;
}

#pragma mark - Smart Selection

- (void)smartSelectWithEvent:(NSEvent *)event {
    const VT100GridAbsCoord coord = [self.delegate urlActionHelper:self
                                                  absCoordForEvent:event
                                          allowRightMarginOverflow:NO];
    [self smartSelectAtAbsoluteCoord:coord ignoringNewlines:NO];
}

- (BOOL)smartSelectAtAbsoluteCoord:(VT100GridAbsCoord)coord ignoringNewlines:(BOOL)ignoringNewlines {
    VT100GridAbsWindowedRange range;
    SmartMatch *smartMatch = [self smartSelectAtAbsoluteCoord:coord
                                                           to:&range
                                             ignoringNewlines:ignoringNewlines
                                               actionRequired:NO
                                              respectDividers:[[NSUserDefaults standardUserDefaults] boolForKey:kSelectionRespectsSoftBoundariesKey]];

    iTermSelection *selection = [self.delegate urlActionHelperSelection:self];
    [selection beginSelectionAtAbsCoord:range.coordRange.start
                                   mode:kiTermSelectionModeCharacter
                                 resume:NO
                                 append:NO];
    [selection moveSelectionEndpointTo:range.coordRange.end];
    if (!ignoringNewlines) {
        // TODO(georgen): iTermSelection doesn't have a mode for smart selection ignoring newlines.
        // If that flag is set, it's better to leave the selection in character mode because you can
        // still extend a selection with shift-click. If we put it in smart mode, extending would
        // get confused.
        selection.selectionMode = kiTermSelectionModeSmart;
    }
    [selection endLiveSelection];
    return smartMatch != nil;
}

@end
