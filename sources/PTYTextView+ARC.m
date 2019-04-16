//
//  PTYTextView+ARC.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import "PTYTextView+ARC.h"

#import "DebugLogging.h"
#import "FileTransferManager.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermImageInfo.h"
#import "iTermLaunchServices.h"
#import "iTermLocalHostNameGuesser.h"
#import "iTermTextExtractor.h"
#import "iTermURLActionFactory.h"
#import "NSObject+iTerm.h"
#import "NSURL+iTerm.h"
#import "PTYTextView+Private.h"
#import "SCPPath.h"
#import "URLAction.h"

@implementation PTYTextView (ARC)

#pragma mark - Attributes

- (NSColor *)selectionBackgroundColor {
    CGFloat alpha = [self useTransparency] ? 1 - self.transparency : 1;
    return [[self.colorMap processedBackgroundColorForBackgroundColor:[self.colorMap colorForKey:kColorMapSelection]] colorWithAlphaComponent:alpha];
}

- (NSColor *)selectedTextColor {
    return [self.colorMap processedTextColorForTextColor:[self.colorMap colorForKey:kColorMapSelectedText]
                                     overBackgroundColor:[self selectionBackgroundColor]
                                  disableMinimumContrast:NO];
}

#pragma mark - Coordinate Space Conversions

- (NSPoint)clickPoint:(NSEvent *)event allowRightMarginOverflow:(BOOL)allowRightMarginOverflow {
    NSPoint locationInWindow = [event locationInWindow];
    return [self windowLocationToRowCol:locationInWindow
               allowRightMarginOverflow:allowRightMarginOverflow];
}

// TODO: this should return a VT100GridCoord but it confusingly returns an NSPoint.
//
// If allowRightMarginOverflow is YES then the returned value's x coordinate may be equal to
// dataSource.width. If NO, then it will always be less than dataSource.width.
- (NSPoint)windowLocationToRowCol:(NSPoint)locationInWindow
         allowRightMarginOverflow:(BOOL)allowRightMarginOverflow {
    NSPoint locationInTextView = [self convertPoint:locationInWindow fromView: nil];

    VT100GridCoord coord = [self coordForPoint:locationInTextView allowRightMarginOverflow:allowRightMarginOverflow];
    return NSMakePoint(coord.x, coord.y);
}

- (VT100GridCoord)coordForPoint:(NSPoint)locationInTextView
       allowRightMarginOverflow:(BOOL)allowRightMarginOverflow {
    int x, y;
    int width = [self.dataSource width];

    x = (locationInTextView.x - [iTermAdvancedSettingsModel terminalMargin] + self.charWidth * [iTermAdvancedSettingsModel fractionOfCharacterSelectingNextNeighbor]) / self.charWidth;
    if (x < 0) {
        x = 0;
    }
    y = locationInTextView.y / self.lineHeight;

    int limit;
    if (allowRightMarginOverflow) {
        limit = width;
    } else {
        limit = width - 1;
    }
    x = MIN(x, limit);
    y = MIN(y, [self.dataSource numberOfLines] - 1);

    return VT100GridCoordMake(x, y);
}

#pragma mark - Query Coordinates

- (iTermImageInfo *)imageInfoAtCoord:(VT100GridCoord)coord {
    if (coord.x < 0 ||
        coord.y < 0 ||
        coord.x >= [self.dataSource width] ||
        coord.y >= [self.dataSource numberOfLines]) {
        return nil;
    }
    screen_char_t* theLine = [self.dataSource getLineAtIndex:coord.y];
    if (theLine && theLine[coord.x].image) {
        return GetImageInfo(theLine[coord.x].code);
    } else {
        return nil;
    }
}

#pragma mark - URL Actions

- (BOOL)ignoreHardNewlinesInURLs {
    if ([iTermAdvancedSettingsModel ignoreHardNewlinesInURLs]) {
        return YES;
    }
    return [self.delegate textViewInInteractiveApplication];
}

- (void)computeURLActionForCoord:(VT100GridCoord)coord
                      completion:(void (^)(URLAction *))completion {
    [self urlActionForClickAtX:coord.x
                             y:coord.y
        respectingHardNewlines:![self ignoreHardNewlinesInURLs]
                    completion:completion];
}

- (URLAction *)urlActionForClickAtX:(int)x y:(int)y {
    // I tried respecting hard newlines if that is a legal URL, but that's such a broad definition
    // that it doesn't work well. Hard EOLs mid-url are very common. Let's try always ignoring them.
    __block URLAction *action = nil;
    [self urlActionForClickAtX:x
                             y:y
        respectingHardNewlines:![self ignoreHardNewlinesInURLs]
                    completion:^(URLAction *result) {
                        action = result;
                    }];
    return action;
}

- (void)urlActionForClickAtX:(int)x
                           y:(int)y
      respectingHardNewlines:(BOOL)respectHardNewlines
                  completion:(void (^)(URLAction *))completion {
    DLog(@"urlActionForClickAt:%@,%@ respectingHardNewlines:%@",
         @(x), @(y), @(respectHardNewlines));
    if (y < 0) {
        completion(nil);
        return;
    }
    const VT100GridCoord coord = VT100GridCoordMake(x, y);
    iTermImageInfo *imageInfo = [self imageInfoAtCoord:coord];
    if (imageInfo) {
        completion([URLAction urlActionToOpenImage:imageInfo]);
        return;
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self.dataSource];
    if ([extractor characterAt:coord].code == 0) {
        completion(nil);
        return;
    }
    [extractor restrictToLogicalWindowIncludingCoord:coord];

    NSString *workingDirectory = [self.dataSource workingDirectoryOnLine:y];
    DLog(@"According to data source, the working directory on line %d is %@", y, workingDirectory);
    if (!workingDirectory) {
        // Well, just try the current directory then.
        DLog(@"That failed, so try to get the current working directory...");
        workingDirectory = [self.delegate textViewCurrentWorkingDirectory];
        DLog(@"It is %@", workingDirectory);
    }

    [iTermURLActionFactory urlActionAtCoord:VT100GridCoordMake(x, y)
                        respectHardNewlines:respectHardNewlines
                           workingDirectory:workingDirectory ?: @""
                                 remoteHost:[self.dataSource remoteHostOnLine:y]
                                  selectors:[self smartSelectionActionSelectorDictionary]
                                      rules:self.smartSelectionRules
                                  extractor:extractor
                  semanticHistoryController:self.semanticHistoryController
                                pathFactory:^SCPPath *(NSString *path, int line) {
                                    return [self.dataSource scpPathForFile:path onLine:line];
                                }
                                 completion:completion];
}

- (void)openTargetWithEvent:(NSEvent *)event inBackground:(BOOL)openInBackground {
    // Command click in place.
    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
    const VT100GridCoord coord = VT100GridCoordMake(clickPoint.x, clickPoint.y);
    __weak __typeof(self) weakSelf = self;
    NSInteger generation = ++_openTargetGeneration;
    DLog(@"Look up URL action for coord %@, generation %@", VT100GridCoordDescription(coord), @(generation));
    [self computeURLActionForCoord:coord
                        completion:^(URLAction *action) {
                            [weakSelf finishOpeningTargetWithEvent:event
                                                             coord:coord
                                                      inBackground:openInBackground
                                                            action:action
                                                        generation:generation];
                        }];
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

    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self.dataSource];
    DLog(@"openTargetWithEvent generation %@ has action=%@", @(generation), action);
    if (action) {
        switch (action.actionType) {
            case kURLActionOpenExistingFile: {
                NSString *extendedPrefix = [extractor wrappedStringAt:coord
                                                              forward:NO
                                                  respectHardNewlines:![self ignoreHardNewlinesInURLs]
                                                             maxChars:[iTermAdvancedSettingsModel maxSemanticHistoryPrefixOrSuffix]
                                                    continuationChars:nil
                                                  convertNullsToSpace:YES
                                                               coords:nil];
                NSString *extendedSuffix = [extractor wrappedStringAt:coord
                                                              forward:YES
                                                  respectHardNewlines:![self ignoreHardNewlinesInURLs]
                                                             maxChars:[iTermAdvancedSettingsModel maxSemanticHistoryPrefixOrSuffix]
                                                    continuationChars:nil
                                                  convertNullsToSpace:YES
                                                               coords:nil];
                if (![self openSemanticHistoryPath:action.fullPath
                                     orRawFilename:action.rawFilename
                                  workingDirectory:action.workingDirectory
                                        lineNumber:action.lineNumber
                                      columnNumber:action.columnNumber
                                            prefix:extendedPrefix
                                            suffix:extendedSuffix]) {
                    [self findUrlInString:action.string andOpenInBackground:openInBackground];
                }
                break;
            }
            case kURLActionOpenURL: {
                NSURL *url = [NSURL URLWithUserSuppliedString:action.string];
                if ([url.scheme isEqualToString:@"file"] &&
                    url.host.length > 0 &&
                    ![url.host isEqualToString:[[iTermLocalHostNameGuesser sharedInstance] name]]) {
                    SCPPath *path = [[SCPPath alloc] init];
                    path.path = url.path;
                    path.hostname = url.host;
                    path.username = [PTYTextView usernameToDownloadFileOnHost:url.host];
                    if (path.username == nil) {
                        return;
                    }
                    [self downloadFileAtSecureCopyPath:path
                                           displayName:url.path.lastPathComponent
                                        locationInView:action.range.coordRange];
                } else {
                    [self openURL:url inBackground:openInBackground];
                }
                break;
            }

            case kURLActionSmartSelectionAction: {
                DLog(@"Run smart selection selector %@", NSStringFromSelector(action.selector));
                [self it_performNonObjectReturningSelector:action.selector withObject:action];
                break;
            }

            case kURLActionOpenImage:
                DLog(@"Open image");
                [[NSWorkspace sharedWorkspace] openFile:[(iTermImageInfo *)action.identifier nameForNewSavedTempFile]];
                break;

            case kURLActionSecureCopyFile:
                DLog(@"Secure copy file.");
                [self downloadFileAtSecureCopyPath:action.identifier
                                       displayName:action.string
                                    locationInView:action.range.coordRange];
                break;
        }
    }
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
    NSString* escapedString = [trimmedURLString stringByEscapingForURL];

    NSURL *url = [NSURL URLWithString:escapedString];
    [self openURL:url inBackground:background];
}

#pragma mark Secure Copy

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

- (void)downloadFileAtSecureCopyPath:(SCPPath *)scpPath
                         displayName:(NSString *)name
                      locationInView:(VT100GridCoordRange)range {
    [self.delegate startDownloadOverSCP:scpPath];

    NSDictionary *attributes =
    @{ NSForegroundColorAttributeName: [self selectedTextColor],
       NSBackgroundColorAttributeName: [self selectionBackgroundColor],
       NSFontAttributeName: self.primaryFont.font };
    NSSize size = [name sizeWithAttributes:attributes];
    size.height = self.lineHeight;
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [name drawAtPoint:NSMakePoint(0, 0) withAttributes:attributes];
    [image unlockFocus];

    NSRect windowRect = [self convertRect:NSMakeRect(range.start.x * self.charWidth + [iTermAdvancedSettingsModel terminalMargin],
                                                     range.start.y * self.lineHeight,
                                                     0,
                                                     0)
                                   toView:nil];
    NSPoint point = [[self window] convertRectToScreen:windowRect].origin;
    point.y -= self.lineHeight;
    [[FileTransferManager sharedInstance] animateImage:image
                            intoDownloadsMenuFromPoint:point
                                              onScreen:[[self window] screen]];
}

#pragma mark - Open URL

// If iTerm2 is the handler for the scheme, then the profile is launched directly.
// Otherwise it's passed to the OS to launch.
- (void)openURL:(NSURL *)url inBackground:(BOOL)background {
    DLog(@"openURL:%@ inBackground:%@", url, @(background));

    Profile *profile = [[iTermLaunchServices sharedInstance] profileForScheme:[url scheme]];
    if (profile) {
        [self.delegate launchProfileInCurrentTerminal:profile withURL:url.absoluteString];
    } else if (background) {
        [[NSWorkspace sharedWorkspace] openURLs:@[ url ]
                        withAppBundleIdentifier:nil
                                        options:NSWorkspaceLaunchWithoutActivation
                 additionalEventParamDescriptor:nil
                              launchIdentifiers:nil];
    } else {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

#pragma mark - Smart Selection

- (NSDictionary<NSNumber *, NSString *> *)smartSelectionActionSelectorDictionary {
    // The selector's name must begin with contextMenuAction to
    // pass validateMenuItem.
    return @{ @(kOpenFileContextMenuAction): NSStringFromSelector(@selector(contextMenuActionOpenFile:)),
              @(kOpenUrlContextMenuAction): NSStringFromSelector(@selector(contextMenuActionOpenURL:)),
              @(kRunCommandContextMenuAction): NSStringFromSelector(@selector(contextMenuActionRunCommand:)),
              @(kRunCoprocessContextMenuAction): NSStringFromSelector(@selector(contextMenuActionRunCoprocess:)),
              @(kSendTextContextMenuAction): NSStringFromSelector(@selector(contextMenuActionSendText:)),
              @(kRunCommandInWindowContextMenuAction): NSStringFromSelector(@selector(contextMenuActionRunCommandInWindow:)) };
}

#pragma mark - Context Menu Actions

- (void)contextMenuActionOpenFile:(id)sender {
    DLog(@"Open file: '%@'", [sender representedObject]);
    [[NSWorkspace sharedWorkspace] openFile:[[sender representedObject] stringByExpandingTildeInPath]];
}

- (void)contextMenuActionOpenURL:(id)sender {
    NSURL *url = [NSURL URLWithUserSuppliedString:[sender representedObject]];
    if (url) {
        DLog(@"Open URL: %@", [sender representedObject]);
        [[NSWorkspace sharedWorkspace] openURL:url];
    } else {
        DLog(@"%@ is not a URL", [sender representedObject]);
    }
}

- (void)contextMenuActionRunCommand:(id)sender {
    NSString *command = [sender representedObject];
    DLog(@"Run command: %@", command);
    [NSThread detachNewThreadSelector:@selector(runCommand:)
                             toTarget:[self class]
                           withObject:command];
}

- (void)contextMenuActionRunCommandInWindow:(id)sender {
    NSString *command = [sender representedObject];
    DLog(@"Run command in window: %@", command);
    [[iTermController sharedInstance] openSingleUseWindowWithCommand:command];
}

+ (void)runCommand:(NSString *)command {
    @autoreleasepool {
        system([command UTF8String]);
    }
}

- (void)contextMenuActionRunCoprocess:(id)sender {
    NSString *command = [sender representedObject];
    DLog(@"Run coprocess: %@", command);
    [self.delegate launchCoprocessWithCommand:command];
}

- (void)contextMenuActionSendText:(id)sender {
    NSString *command = [sender representedObject];
    DLog(@"Send text: %@", command);
    [self.delegate insertText:command];
}


@end
