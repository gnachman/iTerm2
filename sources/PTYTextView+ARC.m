//
//  PTYTextView+ARC.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import "PTYTextView+ARC.h"

#import "DebugLogging.h"
#import "FileTransferManager.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermActionsMenuController.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBackgroundCommandRunner.h"
#import "iTermCommandRunner.h"
#import "iTermController.h"
#import "iTermImageInfo.h"
#import "iTermLaunchServices.h"
#import "iTermMouseCursor.h"
#import "iTermNotificationController.h"
#import "iTermPreferences.h"
#import "iTermScriptConsole.h"
#import "iTermScriptHistory.h"
#import "iTermSelection.h"
#import "iTermShellIntegrationWindowController.h"
#import "iTermSlowOperationGateway.h"
#import "iTermSnippetsMenuController.h"
#import "iTermSnippetsModel.h"
#import "iTermTextExtractor.h"
#import "iTermTextPopoverViewController.h"
#import "iTermURLActionFactory.h"
#import "iTermURLStore.h"
#import "iTermWebViewWrapperViewController.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSSavePanel+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "PasteboardHistory.h"
#import "PTYMouseHandler.h"
#import "PTYNoteViewController.h"
#import "PTYTextView+Private.h"
#import "SCPPath.h"
#import "SearchResult.h"
#import "ToastWindowController.h"
#import "URLAction.h"
#import "VT100Terminal.h"

#import <WebKit/WebKit.h>

static const NSUInteger kDragPaneModifiers = (NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagShift);
static const NSUInteger kRectangularSelectionModifiers = (NSEventModifierFlagCommand | NSEventModifierFlagOption);
static const NSUInteger kRectangularSelectionModifierMask = (kRectangularSelectionModifiers | NSEventModifierFlagControl);

@interface PTYTextView (ARCPrivate)<iTermShellIntegrationWindowControllerDelegate,
iTermCommandInfoViewControllerDelegate>
@end


@implementation PTYTextView (ARC)

- (void)initARC {
    _contextMenuHelper.delegate = self;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(imageDidLoad:)
                                                 name:iTermImageDidLoad
                                               object:nil];
}

#pragma mark - NSResponder

- (BOOL)arcValidateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(sendSnippet:) ||
        item.action == @selector(applyAction:)) {
        return YES;
    }
    if (item.action == @selector(toggleEnableTriggersInInteractiveApps:)) {
        item.state = [self.delegate textViewTriggersAreEnabledInInteractiveApps] ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (item.action == @selector(performFindPanelAction:) && item.tag == NSFindPanelActionSelectAll) {
        return self.findOnPageHelper.searchResults.count > 0;
    }
    if (item.action == @selector(renderSelection:)) {
        return [self.selection hasSelection] && self.selection.allSubSelections.count == 1 && !self.selection.live && ![self absRangeIntersectsPortholes:self.selection.spanningAbsRange];
    }
    if (item.action == @selector(sshDisconnect:)) {
        NSString *name = [self.delegate textViewCurrentSSHSessionName];
        if (name) {
            item.title = [NSString stringWithFormat:@"Disconnect from %@", name];
            return YES;
        } else {
            item.title = @"Disconnect";
        }
    }
    if (item.action == @selector(performNaturalLanguageQuery:)) {
        return YES;
    }
    return NO;
}

#pragma mark - Actions

- (IBAction)renderSelection:(id)sender {
    VT100GridAbsCoordRange absRange = self.selection.spanningAbsRange;
    [self.selection.allSubSelections[0] setAbsRange:VT100GridAbsWindowedRangeMake(absRange, 0, self.dataSource.width)];
    [self renderRange:absRange type:nil filename:nil forceWide:NO];
    [self.selection clearSelection];
}

- (IBAction)sshDisconnect:(id)sender {
    [self.delegate textViewDisconnectSSH];
}

- (IBAction)performNaturalLanguageQuery:(id)sender {
    [self.delegate textViewPerformNaturalLanguageQuery];
}

#pragma mark - Coordinate Space Conversions

// NOTE: This should actually be a VT100GridCoord.
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

    x = (locationInTextView.x - [iTermPreferences intForKey:kPreferenceKeySideMargins] + self.charWidth * [iTermAdvancedSettingsModel fractionOfCharacterSelectingNextNeighbor]) / self.charWidth;
    if (x < 0) {
        x = 0;
    }

    // The rect we draw may be different than the document visible rect. Mouse events should be
    // interpreted relative to what is drawn. We compute the click location relative to the
    // documentVisibleRect and then convert it to be in the space of the adjustedDocumentVisibleRect
    // (which corresponds to what the thinks they clicked on).
    const NSRect adjustedVisibleRect = [self adjustedDocumentVisibleRect];
    const NSRect scrollviewVisibleRect = [self.enclosingScrollView documentVisibleRect];
    const CGFloat relativeY = locationInTextView.y - NSMinY(scrollviewVisibleRect);
    const CGFloat correctedY = NSMinY(adjustedVisibleRect) + relativeY;

    y = correctedY / self.lineHeight;

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

// Returns VT100GridCoordInvalid if event not on any cell
- (VT100GridCoord)coordForEvent:(NSEvent *)event {
    const NSPoint screenPoint = [NSEvent mouseLocation];
    return [self coordForMouseLocation:screenPoint];
}

- (VT100GridCoord)coordForMouseLocation:(NSPoint)screenPoint {
    const NSRect windowRect = [[self window] convertRectFromScreen:NSMakeRect(screenPoint.x,
                                                                              screenPoint.y,
                                                                              0,
                                                                              0)];
    const NSPoint locationInTextView = [self convertPoint:windowRect.origin fromView: nil];
    if (!NSPointInRect(locationInTextView, [self bounds])) {
        return VT100GridCoordInvalid;
    }

    NSPoint viewPoint = [self windowLocationToRowCol:windowRect.origin allowRightMarginOverflow:NO];
    return VT100GridCoordMake(viewPoint.x, viewPoint.y);
}

- (NSPoint)pointForCoord:(VT100GridCoord)coord {
    return NSMakePoint([iTermPreferences intForKey:kPreferenceKeySideMargins] + coord.x * self.charWidth,
                       coord.y * self.lineHeight);
}

- (VT100GridCoord)coordForPointInWindow:(NSPoint)point {
    // TODO: Merge this function with windowLocationToRowCol.
    NSPoint p = [self windowLocationToRowCol:point allowRightMarginOverflow:NO];
    return VT100GridCoordMake(p.x, p.y);
}

#pragma mark - Query Coordinates

- (id<iTermImageInfoReading>)imageInfoAtCoord:(VT100GridCoord)coord {
    if (coord.x < 0 ||
        coord.y < 0 ||
        coord.x >= [self.dataSource width] ||
        coord.y >= [self.dataSource numberOfLines]) {
        return nil;
    }
    const screen_char_t *theLine = [self.dataSource screenCharArrayForLine:coord.y].line;
    if (theLine && theLine[coord.x].image) {
        return GetImageInfo(theLine[coord.x].code);
    } else {
        return nil;
    }
}

#pragma mark - Semantic History

- (void)handleSemanticHistoryItemDragWithEvent:(NSEvent *)event
                                         coord:(VT100GridCoord)coord {
    DLog(@"do semantic history check");

    // Drag a file handle (only possible when there is no selection).
    __weak __typeof(self) weakSelf = self;
    [_urlActionHelper urlActionForClickAtCoord:coord completion:^(URLAction *action) {
        [weakSelf finishHandlingSemanticHistoryItemDragWithEvent:event action:action];
    }];
}

- (void)finishHandlingSemanticHistoryItemDragWithEvent:(NSEvent *)event
                                                action:(URLAction *)action {
    if (!_mouseHandler.semanticHistoryDragged) {
        return;
    }
    const VT100GridCoord coord = [self coordForMouseLocation:[NSEvent mouseLocation]];
    if (!VT100GridWindowedRangeContainsCoord(action.range, coord)) {
        return;
    }
    NSString *path = action.fullPath;
    if (path == nil) {
        DLog(@"path is nil");
        return;
    }

    NSPoint dragPosition;
    NSImage *dragImage;

    dragImage = [[NSWorkspace sharedWorkspace] iconForFile:path];
    dragPosition = [self convertPoint:[event locationInWindow] fromView:nil];
    dragPosition.x -= [dragImage size].width / 2;

    NSURL *url = [NSURL fileURLWithPath:path];

    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setString:[url absoluteString] forType:(NSString *)kUTTypeFileURL];
    NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pbItem];
    [dragItem setDraggingFrame:NSMakeRect(dragPosition.x, dragPosition.y, dragImage.size.width, dragImage.size.height)
                      contents:dragImage];
    NSDraggingSession *draggingSession = [self beginDraggingSessionWithItems:@[ dragItem ]
                                                                       event:event
                                                                      source:self];

    draggingSession.animatesToStartingPositionsOnCancelOrFail = YES;
    draggingSession.draggingFormation = NSDraggingFormationNone;
    [_mouseHandler didDragSemanticHistory];
    DLog(@"did semantic history drag");
}

#pragma mark - Underlined Actions

- (BOOL)shouldUnderlineLinkUnderCursorForEvent:(NSEvent *)event {
    const BOOL commandPressed = ([event it_modifierFlags] & NSEventModifierFlagCommand) != 0;
    if (!commandPressed) {
        return NO;
    }
    const VT100GridCoord coord = [self coordForEvent:event];
    const BOOL semanticHistoryAllowed = (self.window.isKeyWindow ||
                                         [iTermAdvancedSettingsModel cmdClickWhenInactiveInvokesSemanticHistory]);
    if (!semanticHistoryAllowed) {
        return NO;
    }
    if (VT100GridCoordEquals(coord, VT100GridCoordInvalid)) {
        return NO;
    }
    if (![iTermPreferences boolForKey:kPreferenceKeyCmdClickOpensURLs]) {
        return NO;
    }
    if (coord.y < 0) {
        return NO;
    }
    return YES;
}

// Update range of underlined chars indicating cmd-clickable url.
- (void)updateUnderlinedURLs:(NSEvent *)event {
    const BOOL commandPressed = ([event it_modifierFlags] & NSEventModifierFlagCommand) != 0;
    DLog(@"command pressed=%@ flags=%llx", @(commandPressed), (unsigned long long)event.it_modifierFlags);
    // Optimization
    if (!commandPressed && ![self hasUnderline]) {
        DLog(@"Command not pressed AND I don't have an underline");
        return;
    }
    if (!commandPressed || ![self shouldUnderlineLinkUnderCursorForEvent:event]) {
        const BOOL changedUnderline = [self removeUnderline];
        const BOOL cursorChanged = [self updateCursor:event action:nil];
        DLog(@"Don't want an underline. changedUnderline=%@ cursorChanged=%@", @(changedUnderline), @(cursorChanged));
        if (changedUnderline || cursorChanged) {
            [self requestDelegateRedraw];
        }
        return;
    }
    [self updateCursorAndUnderlinedRange:event];
}

- (void)updateCursorAndUnderlinedRange:(NSEvent *)event {
    DLog(@"updateCursorAndUnderlinedRange:%@", event);
    const VT100GridCoord coord = [self coordForEvent:event];
    __weak __typeof(self) weakSelf = self;
    DLog(@"updateUnderlinedURLs in screen:\n%@", [self.dataSource compactLineDumpWithContinuationMarks]);
    [self.lastUrlActionCanceler cancelOperation];
    self.lastUrlActionCanceler = nil;
    DLog(@"Request action for click at %@", VT100GridCoordDescription(coord));
    if (![self shouldUnderlineLinkUnderCursorForEvent:event]) {
        [self finishUpdatingUnderlinesWithAction:nil event:event];
        return;
    }
    self.lastUrlActionCanceler =
    [_urlActionHelper urlActionForClickAtCoord:coord completion:^(URLAction *action) {
        DLog(@"Action for click at %@ is %@", VT100GridCoordDescription(coord), action);
        [weakSelf finishUpdatingUnderlinesWithAction:action
                                               event:event];
    }];
}

- (void)finishUpdatingUnderlinesWithAction:(URLAction *)action
                                     event:(NSEvent *)event {
    DLog(@"finishUpdatingUnderlinesWithAction:%@", action);
    if (!action) {
        DLog(@"No action: remove underline");
        [self removeUnderline];
        [self updateCursor:event action:action];
        return;
    }
    DLog(@"There is an action");
    const VT100GridCoord coord = [self coordForMouseLocation:[NSEvent mouseLocation]];
    if (!VT100GridWindowedRangeContainsCoord(action.range, coord)) {
        DLog(@"Mouse not in action's range");
        return;
    }

    if ([iTermAdvancedSettingsModel enableUnderlineSemanticHistoryOnCmdHover]) {
        DLog(@"Setting underlined range to %@", VT100GridWindowedRangeDescription(action.range));
        self.drawingHelper.underlinedRange = VT100GridAbsWindowedRangeFromRelative(action.range,
                                                                                   [self.dataSource totalScrollbackOverflow]);
    }

    DLog(@"Request redraw and update cursor");
    [self requestDelegateRedraw];  // It would be better to just display the underlined/formerly underlined area.
    [self updateCursor:event action:action];
}

#pragma mark - Context Menu

- (NSMenu *)menuForEvent:(NSEvent *)event {
    iTermOffscreenCommandLine *offscreenCommandLine = [self offscreenCommandLineForClickAt:event.locationInWindow];
    if (offscreenCommandLine) {
        return nil;
    }
    if ([_contextMenuHelper markForClick:event requireMargin:YES]) {
        return nil;
    }

    return [_contextMenuHelper menuForEvent:event];
}

#pragma mark - Offscreen Command Line

- (iTermOffscreenCommandLine *)offscreenCommandLineForClickAt:(NSPoint)windowPoint {
    iTermOffscreenCommandLine *offscreenCommandLine = self.drawingHelper.offscreenCommandLine;
    if (offscreenCommandLine) {
        NSRect rect =
        [iTermTextDrawingHelper offscreenCommandLineFrameForVisibleRect:[self adjustedDocumentVisibleRect]
                                                               cellSize:NSMakeSize(self.charWidth, self.lineHeight)
                                                               gridSize:VT100GridSizeMake(self.dataSource.width,
                                                                                          self.dataSource.height)];
        const NSPoint viewPoint = [self convertPoint:windowPoint fromView:nil];
        if (NSPointInRect(viewPoint, rect)) {
            DLog(@"Cursor in OCL");
            return offscreenCommandLine;
        }
        DLog(@"Cursor not in OCL at windowPoint %@, viewPoint %@", NSStringFromPoint(windowPoint), NSStringFromPoint(viewPoint));
    }
    return nil;
}

- (void)presentCommandInfoForOffscreenCommandLine:(iTermOffscreenCommandLine *)offscreenCommandLine
                                            event:(NSEvent *)event
                         fromOffscreenCommandLine:(BOOL)fromOffscreenCommandLine {
    [self presentCommandInfoForMark:offscreenCommandLine.mark
                 absoluteLineNumber:offscreenCommandLine.absoluteLineNumber
                               date:offscreenCommandLine.date
                              event:event
           fromOffscreenCommandLine:fromOffscreenCommandLine];
}

- (void)presentCommandInfoForMark:(id<VT100ScreenMarkReading>)mark
               absoluteLineNumber:(long long)absoluteLineNumber
                             date:(NSDate *)date
                            event:(NSEvent *)event 
         fromOffscreenCommandLine:(BOOL)fromOffscreenCommandLine {
    [self presentCommandInfoForMark:mark
                 absoluteLineNumber:absoluteLineNumber
                               date:date
                              point:event.locationInWindow
           fromOffscreenCommandLine:fromOffscreenCommandLine];
}

// Point is in window coords
- (void)presentCommandInfoForMark:(id<VT100ScreenMarkReading>)mark
               absoluteLineNumber:(long long)absoluteLineNumber
                             date:(NSDate *)date
                            point:(NSPoint)windowPoint
         fromOffscreenCommandLine:(BOOL)fromOffscreenCommandLine {
    long long overflow = self.dataSource.totalScrollbackOverflow;
    const int line = absoluteLineNumber - overflow;
    const VT100GridRange lineRange = [self lineRangeForMark:mark];
    NSString *directory = [self.dataSource workingDirectoryOnLine:line];
    id<VT100RemoteHostReading> remoteHost = [self.dataSource remoteHostOnLine:line];
    const NSPoint point = [self convertPoint:windowPoint
                                    fromView:nil];
    iTermProgress *outputProgress = [[iTermProgress alloc] init];
    iTermRenegablePromise<NSString *> *outputPromise = [self promisedOutputForMark:mark progress:outputProgress];
    [iTermCommandInfoViewController presentMark:mark
                                           date:date
                                      directory:directory
                                     remoteHost:remoteHost
                                     outputSize:[self.dataSource numberOfCellsUsedInRange:lineRange]
                                  outputPromise:outputPromise
                                 outputProgress:outputProgress
                                         inView:self
                       fromOffscreenCommandLine:fromOffscreenCommandLine
                                             at:point
                                       delegate:self];
}

- (VT100GridCoordRange)coordRangeForMark:(id<VT100ScreenMarkReading>)mark {
    return [self.dataSource textViewRangeOfOutputForCommandMark:mark];
}

- (VT100GridRange)lineRangeForMark:(id<VT100ScreenMarkReading>)mark {
    const VT100GridCoordRange coordRange = [self coordRangeForMark:mark];
    return VT100GridRangeMake(coordRange.start.y, coordRange.end.y - coordRange.start.y + 1);
}

- (iTermRenegablePromise<NSString *> *)promisedOutputForMark:(id<VT100ScreenMarkReading>)mark
                                                    progress:(iTermProgress *)outputProgress {
    long long overflow = self.dataSource.totalScrollbackOverflow;
    iTermSelection *selection = [[iTermSelection alloc] init];
    selection.delegate = self;
    const VT100GridCoordRange coordRange = [self coordRangeForMark:mark];
    [selection beginSelectionAtAbsCoord:VT100GridAbsCoordMake(0, coordRange.start.y + overflow)
                                   mode:kiTermSelectionModeLine
                                 resume:NO
                                 append:NO];
    [selection moveSelectionEndpointTo:VT100GridAbsCoordMake(self.dataSource.width, coordRange.end.y + overflow - 1)];
    [selection endLiveSelection];
    return [self promisedStringForSelectedTextCappedAtSize:INT_MAX
                                         minimumLineNumber:0
                                                timestamps:NO
                                                 selection:selection
                                                  progress:outputProgress ?: [[iTermProgress alloc] init]];
}

#pragma mark - Mouse Cursor

- (BOOL)updateCursor:(NSEvent *)event action:(URLAction *)action {
    NSString *hover = nil;
    VT100GridWindowedRange anchorRange = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1), -1, -1);
    BOOL changed = NO;
    if (([[iTermApplication sharedApplication] it_modifierFlags] & kDragPaneModifiers) == kDragPaneModifiers) {
        changed = [self setCursor:[NSCursor openHandCursor]];
    } else if (([[iTermApplication sharedApplication] it_modifierFlags] & kRectangularSelectionModifierMask) == kRectangularSelectionModifiers) {
        changed = [self setCursor:[NSCursor crosshairCursor]];
    } else if (action &&
               ([[iTermApplication sharedApplication] it_modifierFlags] & (NSEventModifierFlagOption | NSEventModifierFlagCommand)) == NSEventModifierFlagCommand) {
        changed = [self setCursor:[NSCursor pointingHandCursor]];
        if (action.hover && action.string.length) {
            hover = action.string;
            anchorRange = action.range;
        }
    } else if ([self mouseIsOverImageInEvent:event]) {
        changed = [self setCursor:[NSCursor arrowCursor]];
    } else if ([_mouseHandler mouseReportingAllowedForEvent:event] &&
               [_mouseHandler terminalWantsMouseReports]) {
        changed = [self setCursor:[iTermMouseCursor mouseCursorOfType:iTermMouseCursorTypeIBeamWithCircle]];
    } else if ([self contextMenu:_contextMenuHelper offscreenCommandLineForClickAt:event.locationInWindow]) {
        changed = [self setCursor:[NSCursor arrowCursor]];
    } else if ([self mouseIsOverButtonInEvent:event]) {
        DLog(@"Mouse is over a button");
        changed = [self setCursor:[NSCursor arrowCursor]];
    } else {
        changed = [self setCursor:self.delegate.textViewDefaultPointer ?: [iTermMouseCursor mouseCursorOfType:iTermMouseCursorTypeIBeam]];
    }
    if (changed) {
        [self.enclosingScrollView setDocumentCursor:cursor_];
    }
    return [self.delegate textViewShowHoverURL:hover anchor:anchorRange];
}

- (BOOL)setCursor:(NSCursor *)cursor {
    if (cursor == cursor_) {
        return NO;
    }
    cursor_ = cursor;
    return YES;
}

- (BOOL)mouseIsOverImageInEvent:(NSEvent *)event {
    NSPoint point = [self clickPoint:event allowRightMarginOverflow:NO];
    return [self imageInfoAtCoord:VT100GridCoordMake(point.x, point.y)] != nil;
}

#pragma mark - Quicklook

- (void)handleQuickLookWithEvent:(NSEvent *)event {
    DLog(@"Quick look with event %@\n%@", event, [NSThread callStackSymbols]);
    const NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:YES];
    const VT100GridCoord coord = VT100GridCoordMake(clickPoint.x, clickPoint.y);
    __weak __typeof(self) weakSelf = self;
    [_urlActionHelper urlActionForClickAtCoord:coord completion:^(URLAction *action) {
        [weakSelf finishHandlingQuickLookWithEvent:event action:action];
    }];
}

- (void)finishHandlingQuickLookWithEvent:(NSEvent *)event
                                  action:(URLAction *)urlAction {
    if (!urlAction && [iTermAdvancedSettingsModel performDictionaryLookupOnQuickLook]) {
        NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:YES];
        [self showDefinitionForWordAt:clickPoint];
        return;
    }
    const VT100GridCoord coord = [self coordForMouseLocation:[NSEvent mouseLocation]];
    if (!VT100GridWindowedRangeContainsCoord(urlAction.range, coord)) {
        return;
    }
    NSURL *url = nil;
    switch (urlAction.actionType) {
        case kURLActionSecureCopyFile:
            url = [urlAction.identifier URL];
            break;

        case kURLActionOpenExistingFile:
            url = [NSURL fileURLWithPath:urlAction.fullPath];
            break;

        case kURLActionOpenImage:
            url = [NSURL fileURLWithPath:[urlAction.identifier nameForNewSavedTempFile]];
            break;

        case kURLActionOpenURL: {
            if (!urlAction.string) {
                break;
            }
            url = [NSURL URLWithUserSuppliedString:urlAction.string];
            if (![[self allowedQuickLookURLSchemes] containsObject:url.scheme]) {
                return;
            }
            if (url && [self showWebkitPopoverAtPoint:event.locationInWindow url:url]) {
                return;
            }
            break;
        }
        case kURLActionShowCommandInfo:
        case kURLActionSmartSelectionAction:
            break;
    }

    if (url) {
        NSPoint windowPoint = event.locationInWindow;
        NSRect windowRect = NSMakeRect(windowPoint.x - self.charWidth / 2,
                                       windowPoint.y - self.lineHeight / 2,
                                       self.charWidth,
                                       self.lineHeight);

        NSRect screenRect = [self.window convertRectToScreen:windowRect];
        self.quickLookController = [[iTermQuickLookController alloc] init];
        [self.quickLookController addURL:url];
        [self.quickLookController showWithSourceRect:screenRect controller:self.window.delegate];
    }
}

- (void)showDefinitionForWordAt:(NSPoint)clickPoint {
    if (clickPoint.y < 0) {
        return;
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self.dataSource];
    VT100GridWindowedRange range =
    [extractor rangeForWordAt:VT100GridCoordMake(clickPoint.x, clickPoint.y)
                maximumLength:kReasonableMaximumWordLength];
    NSAttributedString *word = [extractor contentInRange:range
                                       attributeProvider:^NSDictionary *(screen_char_t theChar, iTermExternalAttribute *ea) {
        return [self charAttributes:theChar
                 externalAttributes:ea
                          processed:NO
        elideDefaultBackgroundColor:NO];
    }
                                              nullPolicy:kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal
                                                     pad:NO
                                      includeLastNewline:NO
                                  trimTrailingWhitespace:YES
                                            cappedAtSize:self.dataSource.width
                                            truncateTail:YES
                                       continuationChars:nil
                                                  coords:nil];
    if (word.length) {
        NSPoint point = [self pointForCoord:range.coordRange.start];
        point.y += self.lineHeight;
        NSDictionary *attributes = [word attributesAtIndex:0 effectiveRange:nil];
        if (attributes[NSFontAttributeName]) {
            NSFont *font = attributes[NSFontAttributeName];
            point.y += font.descender;
        }
        [self showDefinitionForAttributedString:word
                                        atPoint:point];
    }
}

- (BOOL)showWebkitPopoverAtPoint:(NSPoint)pointInWindow url:(NSURL *)url {
    WKWebView *webView = [[iTermWebViewFactory sharedInstance] webViewWithDelegate:nil];
    if (webView) {
        if ([[url.scheme lowercaseString] isEqualToString:@"http"]) {
            [webView loadHTMLString:@"This site cannot be displayed in QuickLook because of Application Transport Security. Only HTTPS URLs can be previewed." baseURL:nil];
        } else {
            NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url];
            [webView loadRequest:request];
        }
        NSPopover *popover = [[NSPopover alloc] init];
        NSViewController *viewController = [[iTermWebViewWrapperViewController alloc] initWithWebView:webView
                                                                                            backupURL:url];
        popover.contentViewController = viewController;
        popover.contentSize = viewController.view.frame.size;
        NSRect rect = NSMakeRect(pointInWindow.x - self.charWidth / 2,
                                 pointInWindow.y - self.lineHeight / 2,
                                 self.charWidth,
                                 self.lineHeight);
        rect = [self convertRect:rect fromView:nil];
        popover.behavior = NSPopoverBehaviorSemitransient;
        popover.delegate = self;
        [popover showRelativeToRect:rect
                             ofView:self
                      preferredEdge:NSRectEdgeMinY];
        return YES;
    } else {
        return NO;
    }
}

#pragma mark - Copy to Pasteboard

// Returns a dictionary to pass to NSAttributedString.
- (NSDictionary *)charAttributes:(screen_char_t)c
              externalAttributes:(iTermExternalAttribute *)ea
                       processed:(BOOL)processed
     elideDefaultBackgroundColor:(BOOL)elideDefaultBackgroundColor {
    BOOL isBold = c.bold;
    BOOL isFaint = c.faint;
    NSColor *fgColor;
    NSColor *bgColor = [self colorForCode:c.backgroundColor
                                    green:c.bgGreen
                                     blue:c.bgBlue
                                colorMode:c.backgroundColorMode
                                     bold:NO
                                    faint:NO
                             isBackground:YES];
    if (c.invisible) {
        fgColor = bgColor;
    } else {
        fgColor = [self colorForCode:c.foregroundColor
                               green:c.fgGreen
                                blue:c.fgBlue
                           colorMode:c.foregroundColorMode
                                bold:isBold
                               faint:isFaint
                        isBackground:NO];
    }
    if (processed) {
        fgColor = [self.colorMap processedTextColorForTextColor:fgColor overBackgroundColor:bgColor disableMinimumContrast:NO];
        bgColor = [self.colorMap processedBackgroundColorForBackgroundColor:bgColor];
    }
    if (!c.invisible) {
        fgColor = [fgColor colorByPremultiplyingAlphaWithColor:bgColor];
    }
    int underlineStyle = (ea.urlCode || c.underline) ? (NSUnderlineStyleSingle | NSUnderlineByWord) : 0;

    BOOL isItalic = c.italic;
    UTF32Char remapped = 0;
    PTYFontInfo *fontInfo = [self getFontForChar:c.code
                                       isComplex:c.complexChar
                                      renderBold:&isBold
                                    renderItalic:&isItalic
                                        remapped:&remapped];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineBreakMode = NSLineBreakByCharWrapping;

    NSFont *font = fontInfo.font;
    if (!font) {
        // Ordinarily fontInfo would never be nil, but it is in unit tests. It's useful to distinguish
        // bold from regular in tests, so we ensure that attribute is correctly set in this test-only
        // path.
        const CGFloat size = [NSFont systemFontSize];
        if (c.bold) {
            font = [NSFont boldSystemFontOfSize:size];
        } else {
            font = [NSFont systemFontOfSize:size];
        }
    }
    if (![iTermAdvancedSettingsModel copyBackgroundColor] || elideDefaultBackgroundColor) {
        if (c.backgroundColorMode == ColorModeAlternate &&
            c.backgroundColor == ALTSEM_DEFAULT) {
            bgColor = [NSColor clearColor];
        }
    }
    NSDictionary *attributes = @{ NSForegroundColorAttributeName: fgColor,
                                  NSBackgroundColorAttributeName: bgColor,
                                  NSFontAttributeName: font,
                                  NSParagraphStyleAttributeName: paragraphStyle,
                                  NSUnderlineStyleAttributeName: @(underlineStyle) };
    if (ea.hasUnderlineColor) {
        NSColor *color = [self colorForCode:ea.underlineColor.red
                                      green:ea.underlineColor.green
                                       blue:ea.underlineColor.blue
                                  colorMode:ea.underlineColor.mode
                                       bold:isBold
                                      faint:isFaint
                               isBackground:NO];
        attributes = [attributes dictionaryBySettingObject:color
                                                    forKey:NSUnderlineColorAttributeName];
    }
    if (remapped) {
        attributes = [attributes dictionaryBySettingObject:@(remapped)
                                                    forKey:iTermReplacementBaseCharacterAttributeName];
    }
    if ([iTermAdvancedSettingsModel excludeBackgroundColorsFromCopiedStyle]) {
        attributes = [attributes dictionaryByRemovingObjectForKey:NSBackgroundColorAttributeName];
    }
    if (ea.urlCode) {
        NSURL *url = [[iTermURLStore sharedInstance] urlForCode:ea.urlCode];
        if (url != nil) {
            attributes = [attributes dictionaryBySettingObject:url forKey:NSLinkAttributeName];
        }
    }

    return attributes;
}

#pragma mark - Indicator Messages

- (void)showIndicatorMessage:(NSString *)message at:(NSPoint)point {
    [_indicatorMessagePopoverViewController.popover close];
    _indicatorMessagePopoverViewController = [[iTermTextPopoverViewController alloc] initWithNibName:@"iTermTextPopoverViewController"
                                                                  bundle:[NSBundle bundleForClass:self.class]];
    _indicatorMessagePopoverViewController.popover.behavior = NSPopoverBehaviorTransient;
    [_indicatorMessagePopoverViewController view];
    _indicatorMessagePopoverViewController.textView.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    _indicatorMessagePopoverViewController.textView.drawsBackground = NO;
    [_indicatorMessagePopoverViewController appendString:message];
    const NSRect textViewFrame = [_indicatorMessagePopoverViewController.view convertRect:_indicatorMessagePopoverViewController.textView.bounds
                                                                                 fromView:_indicatorMessagePopoverViewController.textView];
    const CGFloat horizontalInsets = NSWidth(_indicatorMessagePopoverViewController.view.bounds) - NSWidth(textViewFrame);
    const CGFloat verticalInsets = NSHeight(_indicatorMessagePopoverViewController.view.bounds) - NSHeight(textViewFrame);

    NSRect frame = _indicatorMessagePopoverViewController.view.frame;
    frame.size.width = 200;
    frame.size.height = [_indicatorMessagePopoverViewController.textView.attributedString heightForWidth:frame.size.width - horizontalInsets] + verticalInsets;
    
    _indicatorMessagePopoverViewController.view.frame = frame;
    [_indicatorMessagePopoverViewController.popover showRelativeToRect:NSMakeRect(point.x, point.y, 1, 1)
                                                                ofView:self.enclosingScrollView
                                                         preferredEdge:NSRectEdgeMaxY];
}

#pragma mark - Selected Text

- (iTermPromise<NSString *> *)recordSelection:(iTermSelection *)selection {
    const NSInteger maxSize = 10 * 1000 * 1000;
    DLog(@"Renege on last selection promise");
    // No need to keep working on the last one; if it hasn't been waited on then it'll never be used.
    [[[iTermController sharedInstance] lastSelectionPromise] renege];

    iTermRenegablePromise<NSString *> *promise = [self promisedStringForSelectedTextCappedAtSize:maxSize
                                                                               minimumLineNumber:0
                                                                                      timestamps:NO
                                                                                       selection:selection
                                                                                        progress:nil];
    if (promise) {
        [[iTermController sharedInstance] setLastSelectionPromise:promise];
    }
    return promise;
}

- (BOOL)selectionIsBig {
    return [self selectionIsBig:self.selection];
}

- (BOOL)selectionIsBig:(iTermSelection *)selection {
    return selection.approximateNumberOfLines > 1000;
}


- (iTermSelectionExtractorOptions)commonSelectionOptions {
    iTermSelectionExtractorOptions options = 0;
    const BOOL copyLastNewline = [iTermPreferences boolForKey:kPreferenceKeyCopyLastNewline];
    if (copyLastNewline) {
        options |= iTermSelectionExtractorOptionsCopyLastNewline;
    }
    const BOOL trimWhitespace = [iTermAdvancedSettingsModel trimWhitespaceOnCopy];
    if (trimWhitespace) {
        options |= iTermSelectionExtractorOptionsTrimWhitespace;
    }
    if (self.useCustomBoldColor) {
        options |= iTermSelectionExtractorOptionsUseCustomBoldColor;
    }
    if (self.brightenBold) {
        options |= iTermSelectionExtractorOptionsBrightenBold;
    }
    return options;
}

- (NSString *)selectedTextWithTrailingWhitespace {
    iTermStringSelectionExtractor *extractor =
    [[iTermStringSelectionExtractor alloc] initWithSelection:self.selection
                                                    snapshot:[self.dataSource snapshotDataSource]
                                                     options:iTermSelectionExtractorOptionsCopyLastNewline
                                                    maxBytes:INT_MAX
                                           minimumLineNumber:0];

    iTermRenegablePromise<NSString *> *promise =
    [iTermSelectionPromise string:extractor
                       allowEmpty:YES];
    return [promise wait].maybeFirst;
}

- (iTermRenegablePromise<NSString *> *)promisedStringForSelectedTextCappedAtSize:(int)maxBytes
                                                               minimumLineNumber:(int)minimumLineNumber
                                                                      timestamps:(BOOL)timestamps
                                                                       selection:(iTermSelection *)selection
                                                                        progress:(iTermProgress *)outputProgress {
    iTermStringSelectionExtractor *extractor =
    [[iTermStringSelectionExtractor alloc] initWithSelection:selection
                                                    snapshot:[self.dataSource snapshotDataSource]
                                                     options:[self commonSelectionOptions]
                                                    maxBytes:maxBytes
                                           minimumLineNumber:minimumLineNumber];
    extractor.progress = outputProgress;
    extractor.addTimestamps = timestamps;
    return [iTermSelectionPromise string:extractor
                              allowEmpty:![iTermAdvancedSettingsModel disallowCopyEmptyString]];
}

- (iTermRenegablePromise<NSString *> *)promisedSGRStringForSelectedTextCappedAtSize:(int)maxBytes
                                                                  minimumLineNumber:(int)minimumLineNumber
                                                                         timestamps:(BOOL)timestamps
                                                                          selection:(iTermSelection *)selection {
    // Don't trim whitespace here because it's so useful to get an exact copy.
    iTermSGRSelectionExtractor *extractor =
    [[iTermSGRSelectionExtractor alloc] initWithSelection:selection
                                                 snapshot:[self.dataSource snapshotDataSource]
                                                  options:[self commonSelectionOptions] & ~iTermSelectionExtractorOptionsTrimWhitespace
                                                 maxBytes:maxBytes
                                        minimumLineNumber:minimumLineNumber];
    extractor.addTimestamps = timestamps;
    return [iTermSelectionPromise string:extractor
                              allowEmpty:![iTermAdvancedSettingsModel disallowCopyEmptyString]];
}

- (iTermRenegablePromise<NSAttributedString *> *)promisedAttributedStringForSelectedTextCappedAtSize:(int)maxBytes
                                                                                   minimumLineNumber:(int)minimumLineNumber
                                                                                          timestamps:(BOOL)timestamps
                                                                                           selection:(iTermSelection *)selection {
    iTermCharacterAttributesProvider *provider =
    [[iTermCharacterAttributesProvider alloc] initWithColorMap:self.colorMap
                                            useCustomBoldColor:self.useCustomBoldColor
                                                  brightenBold:self.brightenBold
                                                   useBoldFont:self.useBoldFont
                                                 useItalicFont:self.useItalicFont
                                               useNonAsciiFont:self.useNonAsciiFont
                                           copyBackgroundColor:[iTermAdvancedSettingsModel copyBackgroundColor]
                        excludeBackgroundColorsFromCopiedStyle:[iTermAdvancedSettingsModel excludeBackgroundColorsFromCopiedStyle]
                                                     fontTable:self.fontTable];

    iTermAttributedStringSelectionExtractor *extractor =
    [[iTermAttributedStringSelectionExtractor alloc] initWithSelection:selection
                                                              snapshot:[self.dataSource snapshotDataSource]
                                                               options:[self commonSelectionOptions]
                                                              maxBytes:maxBytes
                                                     minimumLineNumber:minimumLineNumber];
    extractor.addTimestamps = timestamps;
    return [iTermSelectionPromise attributedString:extractor
                       characterAttributesProvider:provider
                                        allowEmpty:![iTermAdvancedSettingsModel disallowCopyEmptyString]];
}

- (void)asynchronouslyVendSelectedTextWithStyle:(iTermCopyTextStyle)style
                                   cappedAtSize:(int)maxBytes
                              minimumLineNumber:(int)minimumLineNumber
                                      selection:(iTermSelection *)selection {
    iTermRenegablePromise *promise = nil;
    NSPasteboardType type = NSPasteboardTypeString;
    switch (style) {
        case iTermCopyTextStyleAttributed:
            promise = [self promisedAttributedStringForSelectedTextCappedAtSize:maxBytes
                                                              minimumLineNumber:minimumLineNumber
                                                                     timestamps:NO
                                                                      selection:selection];
            type = NSPasteboardTypeRTF;
            break;

        case iTermCopyTextStylePlainText:
            promise = [self promisedStringForSelectedTextCappedAtSize:maxBytes
                                                    minimumLineNumber:minimumLineNumber
                                                           timestamps:NO
                                                            selection:selection
                                                             progress:nil];
            type = NSPasteboardTypeString;
            break;

        case iTermCopyTextStyleWithControlSequences:
            promise = [self promisedSGRStringForSelectedTextCappedAtSize:maxBytes
                                                       minimumLineNumber:minimumLineNumber
                                                              timestamps:NO
                                                               selection:selection];
            type = NSPasteboardTypeString;
            break;
    }
    if (promise) {
        [iTermAsyncSelectionProvider copyPromise:promise type:type];
    }
}

- (id)selectedTextWithStyle:(iTermCopyTextStyle)style
               cappedAtSize:(int)maxBytes
          minimumLineNumber:(int)minimumLineNumber
                 timestamps:(BOOL)timestamps
                  selection:(iTermSelection *)selection {
    if (@available(macOS 11.0, *)) {
        [[iTermAsyncSelectionProvider currentProvider] cancel];
    }
    switch (style) {
        case iTermCopyTextStyleAttributed:
            return [[self promisedAttributedStringForSelectedTextCappedAtSize:maxBytes
                                                            minimumLineNumber:minimumLineNumber
                                                                   timestamps:timestamps
                                                                    selection:selection] wait].maybeFirst;

        case iTermCopyTextStylePlainText:
            return [[self promisedStringForSelectedTextCappedAtSize:maxBytes
                                                  minimumLineNumber:minimumLineNumber
                                                         timestamps:timestamps
                                                          selection:selection
                                                           progress:nil] wait].maybeFirst;

        case iTermCopyTextStyleWithControlSequences:
            return [[self promisedSGRStringForSelectedTextCappedAtSize:maxBytes
                                                     minimumLineNumber:minimumLineNumber
                                                            timestamps:timestamps
                                                             selection:selection] wait].maybeFirst;
    }
}

- (NSString *)selectedTextCappedAtSize:(int)maxBytes
                     minimumLineNumber:(int)minimumLineNumber {
    return [self selectedTextWithStyle:iTermCopyTextStylePlainText
                          cappedAtSize:maxBytes
                     minimumLineNumber:minimumLineNumber
                            timestamps:NO
                             selection:self.selection];
}

- (NSAttributedString *)selectedAttributedTextWithPad:(BOOL)pad {
    return [self selectedAttributedTextWithPad:pad selection:self.selection];
}

- (NSAttributedString *)selectedAttributedTextWithPad:(BOOL)pad selection:(iTermSelection *)selection {
    return [self selectedTextWithStyle:iTermCopyTextStyleAttributed
                          cappedAtSize:0
                     minimumLineNumber:0
                            timestamps:NO
                             selection:selection];
}


#pragma mark - iTermURLActionHelperDelegate

- (BOOL)urlActionHelperShouldIgnoreHardNewlines:(iTermURLActionHelper *)helper {
    return [self.delegate textViewInInteractiveApplication];
}

- (id<iTermImageInfoReading>)urlActionHelper:(iTermURLActionHelper *)helper imageInfoAt:(VT100GridCoord)coord {
    return [self imageInfoAtCoord:coord];
}

- (iTermTextExtractor *)urlActionHelperNewTextExtractor:(iTermURLActionHelper *)helper {
    return [iTermTextExtractor textExtractorWithDataSource:self.dataSource];
}

- (void)urlActionHelper:(iTermURLActionHelper *)helper workingDirectoryOnLine:(int)y completion:(void (^)(NSString *))completion {
    NSString *workingDirectory = [self.dataSource workingDirectoryOnLine:y];
    DLog(@"According to data source, the working directory on line %d is %@", y, workingDirectory);
    if (workingDirectory) {
        completion(workingDirectory);
        return;
    }

    // Well, just try the current directory then.
    DLog(@"That failed, so try to get the current working directory...");
    [self.delegate textViewGetCurrentWorkingDirectoryWithCompletion:^(NSString *workingDirectory) {
        DLog(@"It is %@", workingDirectory);
        completion(workingDirectory);
    }];
}

- (SCPPath *)urlActionHelper:(iTermURLActionHelper *)helper secureCopyPathForFile:(NSString *)path onLine:(int)line {
    return [self.dataSource scpPathForFile:path onLine:line];
}

- (VT100GridCoord)urlActionHelper:(iTermURLActionHelper *)helper coordForEvent:(NSEvent *)event allowRightMarginOverflow:(BOOL)allowRightMarginOverflow {
    const NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:allowRightMarginOverflow];
    const VT100GridCoord coord = VT100GridCoordMake(clickPoint.x, clickPoint.y);
    return coord;
}

- (VT100GridAbsCoord)urlActionHelper:(iTermURLActionHelper *)helper
                    absCoordForEvent:(NSEvent *)event
            allowRightMarginOverflow:(BOOL)allowRightMarginOverflow {
    const VT100GridCoord coord = [self urlActionHelper:helper coordForEvent:event allowRightMarginOverflow:allowRightMarginOverflow];
    return VT100GridAbsCoordFromCoord(coord, self.dataSource.totalScrollbackOverflow);
}

- (long long)urlActionTotalScrollbackOverflow:(iTermURLActionHelper *)helper {
    return self.dataSource.totalScrollbackOverflow;
}

- (id<VT100RemoteHostReading>)urlActionHelper:(iTermURLActionHelper *)helper remoteHostOnLine:(int)y {
    return [self.dataSource remoteHostOnLine:y];
}

- (NSDictionary<NSNumber *, NSString *> *)urlActionHelperSmartSelectionActionSelectorDictionary:(iTermURLActionHelper *)helper {
    return [_contextMenuHelper smartSelectionActionSelectorDictionary];
}

- (NSArray<NSDictionary<NSString *, id> *> *)urlActionHelperSmartSelectionRules:(iTermURLActionHelper *)helper {
    return self.smartSelectionRules;
}

- (void)urlActionHelper:(iTermURLActionHelper *)helper startSecureCopyDownload:(SCPPath *)scpPath {
    [self.delegate startDownloadOverSCP:scpPath];
}

- (NSDictionary *)urlActionHelperAttributes:(iTermURLActionHelper *)helper {
    CGFloat alpha = [self useTransparency] ? 1 - self.transparency : 1;
    NSColor *unprocessedColor = [self.colorMap colorForKey:kColorMapSelection];
    NSColor *processedColor = [self.colorMap processedBackgroundColorForBackgroundColor:unprocessedColor];
    NSColor *backgroundColor = [processedColor colorWithAlphaComponent:alpha];

    NSColor *textColor = [self.colorMap processedTextColorForTextColor:[self.colorMap colorForKey:kColorMapSelectedText]
                                                   overBackgroundColor:backgroundColor
                                                disableMinimumContrast:NO];
    NSFont *font = self.fontTable.asciiFont.font;
    NSDictionary *attributes = @{ NSForegroundColorAttributeName: textColor,
                                  NSBackgroundColorAttributeName: backgroundColor,
                                  NSFontAttributeName: font };
    return attributes;
}

- (NSPoint)urlActionHelper:(iTermURLActionHelper *)helper pointForCoord:(VT100GridCoord)coord {
    NSRect windowRect = [self convertRect:NSMakeRect(coord.x * self.charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins],
                                                     coord.y * self.lineHeight,
                                                     0,
                                                     0)
                                   toView:nil];
    NSPoint point = [[self window] convertRectToScreen:windowRect].origin;
    point.y -= self.lineHeight;
    return point;
}

- (NSScreen *)urlActionHelperScreen:(iTermURLActionHelper *)helper {
    return [[self window] screen];
}

- (CGFloat)urlActionHelperLineHeight:(iTermURLActionHelper *)helper {
    return self.lineHeight;
}

- (void)urlActionHelper:(iTermURLActionHelper *)helper launchProfileInCurrentTerminal:(Profile *)profile withURL:(NSURL *)url {
    [self.delegate launchProfileInCurrentTerminal:profile withURL:url.absoluteString];
}

- (iTermVariableScope *)urlActionHelperScope:(iTermURLActionHelper *)helper {
    return [self.delegate textViewVariablesScope];
}

- (id<iTermObject>)urlActionHelperOwner:(iTermURLActionHelper *)helper {
    return self.delegate;
}

- (void)urlActionHelperCopySelectionIfNeeded:(iTermURLActionHelper *)helper {
    if ([self.selection hasSelection] && self.delegate) {
        // if we want to copy our selection, do so
        if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
            [self copySelectionAccordingToUserPreferences];
        }
    }
}

- (nonnull iTermSelection *)urlActionHelperSelection:(nonnull iTermURLActionHelper *)helper {
    return self.selection;
}

- (void)urlActionHelperShowCommandInfoForMark:(id<VT100ScreenMarkReading>)mark coord:(VT100GridCoord)coord {
    const NSPoint point = [self convertPoint:[self pointForCoord:coord] toView:nil];
    [self showCommandInfoForMark:mark at:point];
}

#pragma mark - Install Shell Integration

- (IBAction)installShellIntegration:(id)sender {
    if (_shellIntegrationInstallerWindow.isWindowLoaded &&
        _shellIntegrationInstallerWindow.window.isVisible) {
        return;
    }
    _shellIntegrationInstallerWindow =
    [[iTermShellIntegrationWindowController alloc] initWithWindowNibName:@"iTermShellIntegrationWindowController"];
    [_shellIntegrationInstallerWindow.window makeKeyAndOrderFront:nil];
    _shellIntegrationInstallerWindow.delegate = self;
    [_shellIntegrationInstallerWindow.window center];
}

#pragma mark iTermShellIntegrationWindowControllerDelegate

- (void)shellIntegrationWindowControllerSendText:(NSString *)text {
    [self.delegate sendTextSlowly:text];
}

- (iTermExpect *)shellIntegrationExpect {
    return [self.delegate textViewExpect];
}

#pragma mark - iTermMouseReportingFrustrationDetectorDelegate

- (void)mouseReportingFrustrationDetectorDidDetectFrustration:(iTermMouseReportingFrustrationDetector *)sender {
    if ([self.delegate xtermMouseReporting] && !self.selection.hasSelection) {
        [self.delegate textViewDidDetectMouseReportingFrustration];
    }
}

#pragma mark - Mouse Reporting Frustration Detector

- (void)didCopyToPasteboardWithControlSequence {
    [_mouseHandler didCopyToPasteboardWithControlSequence];
}

#pragma mark - Inline Images

- (void)imageDidLoad:(NSNotification *)notification {
    if ([self missingImageIsVisible:notification.object]) {
        [self requestDelegateRedraw];
    }
}

- (BOOL)missingImageIsVisible:(id<iTermImageInfoReading>)image {
    if (![self.drawingHelper.missingImages containsObject:image.uniqueIdentifier]) {
        return NO;
    }
    return [self imageIsVisible:image];
}

- (BOOL)imageIsVisible:(id<iTermImageInfoReading>)image {
    int firstVisibleLine = [[self enclosingScrollView] documentVisibleRect].origin.y / self.lineHeight;
    int width = [self.dataSource width];
    for (int y = 0; y < [self.dataSource height]; y++) {
        const screen_char_t *theLine = [self.dataSource screenCharArrayForLine:y + firstVisibleLine].line;
        for (int x = 0; x < width; x++) {
            if (theLine && theLine[x].image && GetImageInfo(theLine[x].code) == image) {
                return YES;
            }
        }
    }
    return NO;
}

#pragma mark - iTermContextMenuHelperDelegate

- (NSPoint)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
            clickPoint:(NSEvent *)event
allowRightMarginOverflow:(BOOL)allowRightMarginOverflow {
    return [self clickPoint:event allowRightMarginOverflow:allowRightMarginOverflow];
}

- (NSString *)contextMenuSelectedText:(iTermTextViewContextMenuHelper *)contextMenu
                               capped:(int)maxBytes {
    return [self selectedTextCappedAtSize:maxBytes];
}

- (iTermOffscreenCommandLine *)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
            offscreenCommandLineForClickAt:(NSPoint)windowPoint {
    return [self offscreenCommandLineForClickAt:windowPoint];
}

- (id<VT100ScreenMarkReading>)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
                               markOnLine:(int)line {
    return [self.dataSource markOnLine:line];
}

- (id<VT100ScreenMarkReading>)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
                              markAtCoord:(VT100GridCoord)coord {
    VT100GridWindowedRange range = { 0 };
    return [self.dataSource commandMarkAt:coord range:&range];
}

- (NSString *)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
   workingDirectoryOnLine:(int)line {
    return [self.dataSource workingDirectoryOnLine:line];
}

- (nullable id<iTermImageInfoReading>)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
                                 imageInfoAtCoord:(VT100GridCoord)coord {
    return [self imageInfoAtCoord:coord];
}

- (long long)contextMenuTotalScrollbackOverflow:(iTermTextViewContextMenuHelper *)contextMenu {
    return [self.dataSource totalScrollbackOverflow];
}

- (iTermSelection *)contextMenuSelection:(iTermTextViewContextMenuHelper *)contextMenu {
    return self.selection;
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
       setSelection:(iTermSelection *)newSelection {
    self.selection = newSelection;
}

- (BOOL)contextMenuSelectionIsShort:(iTermTextViewContextMenuHelper *)contextMenu {
    return [self _haveShortSelection];
}

- (BOOL)contextMenuSelectionIsReasonable:(iTermTextViewContextMenuHelper *)contextMenu {
    return [self haveReasonableSelection];
}

- (iTermTextExtractor *)contextMenuTextExtractor:(iTermTextViewContextMenuHelper *)contextMenu {
    return [iTermTextExtractor textExtractorWithDataSource:self.dataSource];
}

- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
  withRelativeCoord:(VT100GridAbsCoord)coord
              block:(void (^ NS_NOESCAPE)(VT100GridCoord coord))block {
    return [self withRelativeCoord:coord block:block];
}

- (nullable SCPPath *)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
                   scpPathForFile:(NSString *)file
                           onLine:(int)line {
    return [self.dataSource scpPathForFile:file onLine:line];
}

- (void)contextMenuSplitVertically:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate textViewSplitVertically:YES withProfileGuid:nil];
}

- (void)contextMenuSplitHorizontally:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate textViewSplitVertically:NO withProfileGuid:nil];
}

- (void)contextMenuMovePane:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate textViewMovePane];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu copyURL:(NSURL *)url {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ]
                       owner:self];
    NSString *copyString = url.absoluteString;
    [pasteboard setString:copyString
                  forType:NSPasteboardTypeString];
    [[PasteboardHistory sharedInstance] save:copyString];
}

- (void)contextMenuSwapSessions:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate textViewSwapPane];
}

- (void)contextMenuSendSelectedText:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate sendText:self.selectedText escaping:iTermSendTextEscapingNone];
}

- (void)contextMenuClearBuffer:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.dataSource clearBuffer];
}

- (void)contextMenuAddAnnotation:(iTermTextViewContextMenuHelper *)contextMenu {
    [self addNote];
}

- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
hasOpenAnnotationInRange:(VT100GridCoordRange)coordRange {
    for (id<PTYAnnotationReading> annotation in [self.dataSource annotationsInRange:coordRange]) {
        PTYNoteViewController *note = (PTYNoteViewController *)annotation.delegate;
        if (note.isNoteHidden) {
            return YES;
        }
    }
    return NO;
}

- (void)contextMenuRevealAnnotations:(iTermTextViewContextMenuHelper *)contextMenu
                                  at:(VT100GridCoord)coord {
    const VT100GridCoordRange coordRange =
        VT100GridCoordRangeMake(coord.x,
                                coord.y,
                                coord.x + 1,
                                coord.y);
    for (id<PTYAnnotationReading> annotation in [self.dataSource annotationsInRange:coordRange]) {
        PTYNoteViewController *note = (PTYNoteViewController *)annotation.delegate;
        [note setNoteHidden:NO];
    }
}

- (void)contextMenuEditSession:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate textViewEditSession];
}

- (void)contextMenuToggleBroadcastingInput:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate textViewToggleBroadcastingInput];
}

- (BOOL)contextMenuHasCoprocess:(iTermTextViewContextMenuHelper *)contextMenu {
    return [self.delegate textViewHasCoprocess];
}

- (void)contextMenuStopCoprocess:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate textViewStopCoprocess];
}

- (void)contextMenuCloseSession:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate textViewCloseWithConfirmation];
}

- (BOOL)contextMenuSessionCanBeRestarted:(iTermTextViewContextMenuHelper *)contextMenu {
    return [self.delegate isRestartable];
}

- (void)contextMenuRestartSession:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate textViewRestartWithConfirmation];
}

- (BOOL)contextMenuCanBurySession:(iTermTextViewContextMenuHelper *)contextMenu {
    return [self.delegate textViewCanBury];
}

- (void)contextMenuBurySession:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate textViewBurySession];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu amend:(NSMenu *)menu {
    if ([[self delegate] respondsToSelector:@selector(menuForEvent:menu:)]) {
        [[self delegate] menuForEvent:nil menu:menu];
    }
}

- (NSControlStateValue)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
     terminalStateForMenuItem:(NSMenuItem *)item {
    return [self.delegate textViewTerminalStateForMenuItem:item] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)contextMenuResetTerminal:(iTermTextViewContextMenuHelper *)contextMenu {
    [self.delegate textViewResetTerminal];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu addContextMenuItems:(NSMenu *)theMenu {
    [self.delegate textViewAddContextMenuItems:theMenu];
}

- (NSArray<NSDictionary *> *)contextMenuSmartSelectionRules:(iTermTextViewContextMenuHelper *)contextMenu {
    return self.smartSelectionRules;
}

- (id<VT100RemoteHostReading>)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu remoteHostOnLine:(int)line {
    return [self.dataSource remoteHostOnLine:line];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu insertText:(NSString *)text {
    [self.delegate insertText:text];
}

- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu hasOutputForCommandMark:(id<VT100ScreenMarkReading>)commandMark {
    return [self.dataSource textViewRangeOfOutputForCommandMark:commandMark].start.x != -1;
}

- (VT100GridCoordRange)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
       rangeOfOutputForCommandMark:(id<VT100ScreenMarkReading>)mark {
    return [self.dataSource textViewRangeOfOutputForCommandMark:mark];
}

- (void)contextMenuCopySelectionAccordingToUserPreferences:(iTermTextViewContextMenuHelper *)contextMenu {
    [self copySelectionAccordingToUserPreferences];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
copyRangeAccordingToUserPreferences:(VT100GridWindowedRange)range {
    iTermSelection *selection = [[iTermSelection alloc] init];
    VT100GridAbsWindowedRange absRange = VT100GridAbsWindowedRangeFromRelative(range,
                                                                               self.dataSource.totalScrollbackOverflow);
    iTermSubSelection *sub = [iTermSubSelection subSelectionWithAbsRange:absRange
                                                                    mode:kiTermSelectionModeCharacter
                                                                   width:self.dataSource.width];
    selection.delegate = self;
    [selection addSubSelection:sub];
    if ([iTermAdvancedSettingsModel copyWithStylesByDefault]) {
        [self copySelectionWithStyles:selection];
    } else {
        [self copySelection:selection];
    }
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
               copy:(NSString *)string {
    const BOOL copied = [self copyString:string];
    if (copied) {
        [ToastWindowController showToastWithMessage:@"Copied"
                                           duration:1.5
                                   screenCoordinate:[NSEvent mouseLocation]
                                          pointSize:12];
    }
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
 runCommandInWindow:(NSString *)command {
    [[iTermController sharedInstance] openSingleUseWindowWithCommand:command
                                                              inject:nil
                                                         environment:nil
                                                                 pwd:nil
                                                             options:iTermSingleUseWindowOptionsDoNotEscapeArguments
                                                      didMakeSession:nil
                                                          completion:nil];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
runCommandInBackground:(NSString *)command {
    iTermBackgroundCommandRunner *runner =
        [[iTermBackgroundCommandRunner alloc] initWithCommand:command
                                                        shell:self.delegate.textViewShell
                                                        title:@"Smart Selection Action"];
    runner.notificationTitle = @"Smart Selection Action Failed";
    [runner run];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
       runCoprocess:(NSString *)command {
    [self.delegate launchCoprocessWithCommand:command];
}

- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
withRelativeCoordRange:(VT100GridAbsCoordRange)range
              block:(void (^ NS_NOESCAPE)(VT100GridCoordRange))block {
    return [self withRelativeCoordRange:range block:block];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
            openURL:(NSURL *)url {
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (NSView *)contextMenuViewForMenu:(iTermTextViewContextMenuHelper *)contextMenu {
    return self;
}

- (void)contextMenu:(nonnull iTermTextViewContextMenuHelper *)contextMenu
toggleTerminalStateForMenuItem:(nonnull NSMenuItem *)item {
    [self.delegate textViewToggleTerminalStateForMenuItem:item];

}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
          saveImage:(id<iTermImageInfoReading>)imageInfo {
    NSSavePanel* panel = [NSSavePanel savePanel];

    NSString *directory = [[NSFileManager defaultManager] downloadsDirectory] ?: NSHomeDirectory();
    [NSSavePanel setDirectoryURL:[NSURL fileURLWithPath:directory] onceForID:@"saveImageAs" savePanel:panel];
    panel.nameFieldStringValue = [imageInfo.filename lastPathComponent];
    panel.allowedFileTypes = @[ @"png", @"bmp", @"gif", @"jp2", @"jpeg", @"jpg", @"tiff" ];
    panel.allowsOtherFileTypes = NO;
    panel.canCreateDirectories = YES;
    [panel setExtensionHidden:NO];

    if ([panel runModal] == NSModalResponseOK) {
        NSString *filename = [[panel URL] path];
        [imageInfo saveToFile:filename];
    }
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu copyImage:(
                                                                             id<iTermImageInfoReading>)imageInfo {
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    NSPasteboardItem *item = imageInfo.pasteboardItem;
    if (item) {
        [pboard clearContents];
        [pboard writeObjects:@[ item ]];
    }
}


- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
          openImage:(id<iTermImageInfoReading>)imageInfo {
    NSString *name = imageInfo.nameForNewSavedTempFile;
    if (name) {
        [[iTermLaunchServices sharedInstance] openFile:name];
    }
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
       inspectImage:(id<iTermImageInfoReading>)imageInfo {
    if (imageInfo) {
        NSString *text = [NSString stringWithFormat:
                          @"Filename: %@\n"
                          @"Dimensions: %d x %d",
                          imageInfo.filename,
                          (int)imageInfo.image.size.width,
                          (int)imageInfo.image.size.height];

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = text;
        [alert addButtonWithTitle:@"OK"];
        [alert layout];
        [alert runModal];
    }
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
toggleAnimationOfImage:(id<iTermImageInfoReading>)imageInfo {
    if (imageInfo) {
        imageInfo.paused = !imageInfo.paused;
        if (!imageInfo.paused) {
            // A redraw is needed to recompute which visible lines are animated
            // and ensure they keep getting redrawn on a fast cadence.
            [self requestDelegateRedraw];
        }
    }
}

- (iTermVariableScope *)contextMenuSessionScope:(iTermTextViewContextMenuHelper *)contextMenu {
    return [self.delegate textViewVariablesScope];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
         invocation:(NSString *)invocation
    failedWithError:(NSError *)error
        forMenuItem:(NSString *)title {
    [self.delegate textViewContextMenuInvocation:invocation failedWithError:error forMenuItem:title];
}

- (void)contextMenuSaveSelectionAsSnippet:(iTermTextViewContextMenuHelper *)contextMenu {
    NSString *selectedText = [self selectedText];
    iTermSnippet *snippet = [[iTermSnippet alloc] initWithTitle:selectedText
                                                          value:selectedText
                                                           guid:[[NSUUID UUID] UUIDString]
                                                           tags:@[]
                                                       escaping:iTermSendTextEscapingNone
                                                        version:[iTermSnippet currentVersion]];
    [[iTermSnippetsModel sharedInstance] addSnippet:snippet];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu addTrigger:(NSString *)text {
    [self.delegate textViewAddTrigger:text];
}

- (id<iTermObject>)contextMenuOwner:(iTermTextViewContextMenuHelper *)contextMenu {
    return self.delegate;
}

- (BOOL)contextMenuSmartSelectionActionsShouldUseInterpolatedStrings:(iTermTextViewContextMenuHelper *)contextMenu {
    return [self.delegate textViewSmartSelectionActionsShouldUseInterpolatedStrings];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu showCommandInfoForMark:(id<VT100ScreenMarkReading>)mark {
    if (!mark.startDate) {
        return;
    }
    const VT100GridCoordRange range = [self.dataSource coordRangeOfAnnotation:mark];
    const long long offset = [self.dataSource totalScrollbackOverflow];
    const VT100GridAbsCoordRange absRange = VT100GridAbsCoordRangeFromCoordRange(range, offset);
    const NSRect frame = [self rectForAbsCoord:absRange.start];
    const NSPoint localPoint = NSMakePoint(NSMidX(frame), NSMidY(frame));
    const NSPoint windowPoint = [self convertPoint:localPoint toView:nil];
    [self presentCommandInfoForMark:mark
                 absoluteLineNumber:absRange.start.y
                               date:mark.startDate
                              point:windowPoint
           fromOffscreenCommandLine:NO];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
    removeNamedMark:(id<VT100ScreenMarkReading>)mark {
    [self.dataSource removeNamedMark:mark];
}

- (NSArray<NSString *> *)allowedQuickLookURLSchemes {
    return @[ @"http", @"https" ];
}

- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
    canQuickLookURL:(NSURL *)url {
    return [[self allowedQuickLookURLSchemes] containsObject:url.scheme];
}

- (void)contextMenuHandleQuickLook:(iTermTextViewContextMenuHelper *)contextMenu
                         url:(NSURL *)url
                  windowCoordinate:(NSPoint)windowCoordinate {
    [self showWebkitPopoverAtPoint:windowCoordinate url:url];
}

- (BOOL)contextMenuCurrentTabHasMultipleSessions:(iTermTextViewContextMenuHelper *)contextMenu {
    return [self.delegate textViewEnclosingTabHasMultipleSessions];
}

#pragma mark - NSResponder Additions

- (void)sendSnippet:(id)sender {
    iTermSnippet *snippet = [iTermSnippet castFrom:[sender representedObject]];
    if (!snippet) {
        return;
    }
    const BOOL option = !!([[iTermApplication sharedApplication] it_modifierFlags] & NSEventModifierFlagOption);
    if (option) {
        // Multiple call sites depend on this (open quickly, menu item, and possibly other stuff added later).
        [self.delegate openAdvancedPasteWithText:snippet.value escaping:snippet.escaping];
    } else {
        [self.delegate sendText:snippet.value escaping:snippet.escaping];
    }
}

- (void)applyAction:(id)sender {
    iTermAction *action = [iTermAction castFrom:[sender representedObject]];
    if (action) {
        [self.delegate textViewApplyAction:action];
    }
}

#pragma mark - Responders

- (IBAction)toggleEnableTriggersInInteractiveApps:(id)sender {
    [self.delegate textViewToggleEnableTriggersInInteractiveApps];
}

#pragma mark - Find on Page

- (void)convertMatchesToSelections {
    [self.selection endLiveSelection];
    [self.selection clearSelection];
    const int width = [self.dataSource width];

    NSArray<iTermSubSelection *> *subs = [self.findOnPageHelper.searchResults.array mapWithBlock:^id(SearchResult *result) {
        if (result.isExternal) {
            [self selectExternalSearchResult:result.externalResult multiple:YES scroll:NO];
            return nil;
        } else {
            const VT100GridAbsWindowedRange range  =
            VT100GridAbsWindowedRangeMake(result.internalAbsCoordRange, 0, 0);
            iTermSubSelection *sub = [iTermSubSelection subSelectionWithAbsRange:range
                                                                            mode:kiTermSelectionModeCharacter
                                                                           width:width];
            return sub;
        }
    }];
    if (!subs.count) {
        return;
    }
    [self.selection addSubSelections:subs];
    [self.window makeFirstResponder:self];
}

#pragma mark - Tracking Child Windows

- (void)trackChildWindow:(id<PTYTrackingChildWindow>)window {
    if (_trackingChildWindows.count == 0) {
        // In case we're in metal and this is out of date.
        _lastVirtualOffset = [self virtualOffset];
    }
    [_trackingChildWindows addObject:window];
    __weak __typeof(self) weakSelf = self;
    __weak __typeof(window) weakWindow = window;
    window.requestRemoval = ^{
        [weakSelf stopTrackingChildWindow:weakWindow];
    };
}

- (void)stopTrackingChildWindow:(id<PTYTrackingChildWindow>)window {
    if (!window) {
        return;
    }
    [_trackingChildWindows removeObject:window];
}

- (void)shiftTrackingChildWindows {
    const CGFloat virtualOffset = [self virtualOffset];
    const CGFloat delta = virtualOffset - _lastVirtualOffset;
    _lastVirtualOffset = virtualOffset;
    [_trackingChildWindows enumerateObjectsUsingBlock:^(id<PTYTrackingChildWindow> child, NSUInteger idx, BOOL * _Nonnull stop) {
        [child shiftVertically:delta];
    }];
}

#pragma mark - Content Navigation

- (ContentNavigationShortcutView *)addShortcutWithRange:(VT100GridAbsCoordRange)range
                                          keyEquivalent:(NSString *)keyEquivalent
                                                 action:(void (^)(id<iTermContentNavigationShortcutView>,
                                                                  NSEvent *))action {
    if (!self.contentNavigationShortcuts) {
        self.contentNavigationShortcuts = [NSMutableArray array];
    }
    iTermContentNavigationShortcut *shortcut = [[iTermContentNavigationShortcut alloc] initWithRange:range
                                                                                       keyEquivalent:keyEquivalent
                                                                                              action:action];
    [self.contentNavigationShortcuts addObject:shortcut];
    return [self addViewForContentNavigationShortcut:shortcut];
}

- (NSRect)rectForAbsCoord:(VT100GridAbsCoord)coord {
    BOOL ok;
    VT100GridCoord relative = VT100GridCoordFromAbsCoord(coord, self.dataSource.totalScrollbackOverflow, &ok);
    if (!ok) {
        return NSZeroRect;
    }
    return [self rectForCoord:relative];
}

- (ContentNavigationShortcutView *)addViewForContentNavigationShortcut:(iTermContentNavigationShortcut *)shortcut
                                                          {
    const NSRect rect = NSUnionRect([self rectForAbsCoord:shortcut.range.start],
                                    [self rectForAbsCoord:shortcut.range.end]);
    ContentNavigationShortcutView *view = [[ContentNavigationShortcutView alloc] initWithShortcut:shortcut
                                                                                           target:rect];
    shortcut.view = view;
    const NSSize size = view.bounds.size;
    view.frame = NSMakeRect(MAX(0, rect.origin.x - size.width / 2),
                            MAX(0, rect.origin.y - size.height / 2),
                            size.width,
                            size.height);
    [self refresh];
    [self addSubview:view];
    [self requestDelegateRedraw];
    [self updateAlphaValue];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAnnotationVisibilityDidChange object:nil];
    [view animateIn];
    return view;
}

- (void)removeContentNavigationShortcuts {
    if (!self.contentNavigationShortcuts.count) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    for (iTermContentNavigationShortcut *shortcut in self.contentNavigationShortcuts) {
        if (!shortcut.view.terminating) {
            [shortcut.view dissolveWithCompletion:^{
                [weakSelf removeContentNavigationShortcutView:shortcut.view];
            }];
        }
    }
    [self clearHighlights:YES];
}

- (void)removeContentNavigationShortcutView:(id<iTermContentNavigationShortcutView>)view {
    [self.contentNavigationShortcuts removeObjectsPassingTest:^BOOL(iTermContentNavigationShortcut *anObject) {
        return anObject.view == view;
    }];
    [[NSView castFrom:view] removeFromSuperview];
    [self refresh];
    [self requestDelegateRedraw];
    [self updateAlphaValue];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAnnotationVisibilityDidChange object:nil];
}

- (void)convertVisibleSearchResultsToContentNavigationShortcutsWithAction:(iTermContentNavigationAction)action {
    [self removeContentNavigationShortcuts];
    const VT100GridRange relativeRange = [self rangeOfVisibleLines];
    const NSRange range = NSMakeRange(relativeRange.location + self.dataSource.totalScrollbackOverflow,
                                      relativeRange.length);
    __weak __typeof(self) weakSelf = self;
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:self.dataSource];
    ContentNavigationShortcutLayerOuter *layerOuter = [[ContentNavigationShortcutLayerOuter alloc] init];
    NSMutableArray<SearchResult *> *results = [NSMutableArray array];
    [self.findOnPageHelper enumerateSearchResultsInRangeOfLines:range
                                                          block:^(SearchResult *result) {
        [results addObject:result];
    }];
    if (results.count == 0) {
        return;
    }
    [results sortUsingComparator:^NSComparisonResult(SearchResult *lhs, SearchResult *rhs) {
        if (lhs.internalAbsStartY == rhs.internalAbsStartY) {
            return [@(lhs.internalStartX) compare:@(rhs.internalStartX)];
        }
        return [@(lhs.internalAbsStartY) compare:@(rhs.internalAbsStartY)];
    }];
    NSInteger i = 0;
    for (SearchResult *result in results) {
        VT100GridCoordRange range = VT100GridCoordRangeFromAbsCoordRange(result.internalAbsCoordRange,
                                                                         self.dataSource.totalScrollbackOverflow);
        VT100GridWindowedRange windowedRange = VT100GridWindowedRangeMake(range, 0, 0);
        NSString *content = [extractor contentInRange:windowedRange
                                    attributeProvider:nil
                                           nullPolicy:kiTermTextExtractorNullPolicyTreatAsSpace
                                                  pad:NO
                                   includeLastNewline:NO
                               trimTrailingWhitespace:YES
                                         cappedAtSize:4096
                                         truncateTail:YES
                                    continuationChars:nil
                                               coords:nil];
        NSString *folder = [self.dataSource workingDirectoryOnLine:range.start.y];
        if (!content.length) {
            return;
        }
        id<VT100RemoteHostReading> remoteHost = [self.dataSource remoteHostOnLine:range.start.y];
        i += 1;
        NSString *keyEquivalent;
        if (i < 10) {
            keyEquivalent = [@(i) stringValue];
        } else if (i < 10 + 26) {
            keyEquivalent = [NSString stringWithLongCharacter:'A' + i - 10];
        } else {
            break;
        }
        ContentNavigationShortcutView *view =
        [self addShortcutWithRange:result.internalAbsCoordRange
                     keyEquivalent:keyEquivalent
                            action:^(id<iTermContentNavigationShortcutView> view,
                                     NSEvent *event){
            switch (action) {
                case iTermContentNavigationActionOpen: {
                    PTYTextView *strongSelf = weakSelf;
                    if (strongSelf) {
                        if (event.modifierFlags & NSEventModifierFlagOption) {
                            [strongSelf copyContentByShortcut:content
                                                        event:event
                                                         view:view
                                                        range:windowedRange];
                        } else {
                            [strongSelf.delegate textViewOpen:content 
                                             workingDirectory:folder
                                                   remoteHost:remoteHost];
                        }
                    }
                    break;
                }
                case iTermContentNavigationActionCopy: {
                    PTYTextView *strongSelf = weakSelf;
                    if (strongSelf) {
                        if (event.modifierFlags & NSEventModifierFlagOption) {
                            [strongSelf.delegate writeTask:content];
                        } else {
                            [strongSelf copyContentByShortcut:content
                                                        event:event
                                                         view:view
                                                        range:windowedRange];
                        }
                    }
                    break;
                }
            }
            [view popWithCompletion:^{
                [weakSelf removeContentNavigationShortcutView:view];
            }];
            [weakSelf.delegate textViewExitShortcutNavigationMode];
        }];
        [layerOuter addView:view];
    }
    [layerOuter layoutWithin:self.enclosingScrollView.documentVisibleRect];
    [self refresh];
    [self.delegate textViewEnterShortcutNavigationMode];
    [self.window makeFirstResponder:self];
}

- (void)copyContentByShortcut:(NSString *)content
                        event:(NSEvent *)event
                         view:(id<iTermContentNavigationShortcutView>)view
                        range:(VT100GridWindowedRange)windowedRange {
    [self copyString:content];
    const NSPoint p = view.centerScreenCoordinate;
    if (p.x == p.x) {
        [ToastWindowController showToastWithMessage:@"Copied"
                                           duration:1
                                   screenCoordinate:p
                                          pointSize:12];
    }
    const VT100GridAbsWindowedRange absWindowedRange =
    VT100GridAbsWindowedRangeFromRelative(windowedRange,
                                          self.dataSource.totalScrollbackOverflow);
    [self selectAbsWindowedCoordRange:absWindowedRange];
}

#pragma mark - iTermCommandInfoViewControllerDelegate

- (void)commandInfoSend:(NSString *)string {
    [self.delegate sendText:string escaping:iTermSendTextEscapingNone];
}

- (void)commandInfoOpenInCompose:(NSString *)string {
    [self.delegate textViewOpenComposer:string];
}

- (void)commandInfoSelectOutput:(id<VT100ScreenMarkReading>)mark {
    [_contextMenuHelper selectOutputOfCommandMark:mark];
}

- (void)commandInfoDisable {
    [self.delegate textViewDisableOffscreenCommandLine];
}

@end
