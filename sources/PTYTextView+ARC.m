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
#import "URLAction.h"
#import "VT100Terminal.h"

#import <WebKit/WebKit.h>

static const NSUInteger kDragPaneModifiers = (NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagShift);
static const NSUInteger kRectangularSelectionModifiers = (NSEventModifierFlagCommand | NSEventModifierFlagOption);
static const NSUInteger kRectangularSelectionModifierMask = (kRectangularSelectionModifiers | NSEventModifierFlagControl);

@interface PTYTextView (ARCPrivate)<iTermShellIntegrationWindowControllerDelegate>
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
    if (item.action == @selector(convertMatchesToSelections:)) {
        return self.findOnPageHelper.searchResults.count > 0;
    }
    return NO;
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

// Update range of underlined chars indicating cmd-clickable url.
- (void)updateUnderlinedURLs:(NSEvent *)event {
    const BOOL commandPressed = ([event it_modifierFlags] & NSEventModifierFlagCommand) != 0;

    // Optimization
    if (!commandPressed && ![self hasUnderline]) {
        return;
    }
    const BOOL semanticHistoryAllowed = (self.window.isKeyWindow ||
                                         [iTermAdvancedSettingsModel cmdClickWhenInactiveInvokesSemanticHistory]);
    const VT100GridCoord coord = [self coordForEvent:event];

    if (!commandPressed ||
        !semanticHistoryAllowed ||
        VT100GridCoordEquals(coord, VT100GridCoordInvalid) ||
        ![iTermPreferences boolForKey:kPreferenceKeyCmdClickOpensURLs] ||
        coord.y < 0) {
        const BOOL changedUnderline = [self removeUnderline];
        const BOOL cursorChanged = [self updateCursor:event action:nil];
        if (changedUnderline || cursorChanged) {
            [self setNeedsDisplay:YES];
        }
        return;
    }

    __weak __typeof(self) weakSelf = self;
    DLog(@"updateUnderlinedURLs in screen:\n%@", [self.dataSource compactLineDumpWithContinuationMarks]);
    [_urlActionHelper urlActionForClickAtCoord:coord completion:^(URLAction *action) {
        [weakSelf finishUpdatingUnderlinesWithAction:action
                                               event:event];
    }];
}

- (void)finishUpdatingUnderlinesWithAction:(URLAction *)action
                                     event:(NSEvent *)event {
    if (!action) {
        [self removeUnderline];
        [self updateCursor:event action:action];
        return;
    }

    const VT100GridCoord coord = [self coordForMouseLocation:[NSEvent mouseLocation]];
    if (!VT100GridWindowedRangeContainsCoord(action.range, coord)) {
        return;
    }

    if ([iTermAdvancedSettingsModel enableUnderlineSemanticHistoryOnCmdHover]) {
        self.drawingHelper.underlinedRange = VT100GridAbsWindowedRangeFromRelative(action.range,
                                                                                   [self.dataSource totalScrollbackOverflow]);
    }

    [self setNeedsDisplay:YES];  // It would be better to just display the underlined/formerly underlined area.
    [self updateCursor:event action:action];
}

#pragma mark - Context Menu

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [_contextMenuHelper menuForEvent:event];
}

#pragma mark - Mouse Cursor

- (BOOL)updateCursor:(NSEvent *)event action:(URLAction *)action {
    NSString *hover = nil;
    BOOL changed = NO;
    if (([event it_modifierFlags] & kDragPaneModifiers) == kDragPaneModifiers) {
        changed = [self setCursor:[NSCursor openHandCursor]];
    } else if (([event it_modifierFlags] & kRectangularSelectionModifierMask) == kRectangularSelectionModifiers) {
        changed = [self setCursor:[NSCursor crosshairCursor]];
    } else if (action &&
               ([event it_modifierFlags] & (NSEventModifierFlagOption | NSEventModifierFlagCommand)) == NSEventModifierFlagCommand) {
        changed = [self setCursor:[NSCursor pointingHandCursor]];
        if (action.hover && action.string.length) {
            hover = action.string;
        }
    } else if ([self mouseIsOverImageInEvent:event]) {
        changed = [self setCursor:[NSCursor arrowCursor]];
    } else if ([_mouseHandler mouseReportingAllowedForEvent:event] &&
               [_mouseHandler terminalWantsMouseReports]) {
        changed = [self setCursor:[iTermMouseCursor mouseCursorOfType:iTermMouseCursorTypeIBeamWithCircle]];
    } else {
        changed = [self setCursor:[iTermMouseCursor mouseCursorOfType:iTermMouseCursorTypeIBeam]];
    }
    if (changed) {
        [self.enclosingScrollView setDocumentCursor:cursor_];
    }
    return [self.delegate textViewShowHoverURL:hover];
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
            if (![@[ @"http", @"https" ] containsObject:url.scheme]) {
                return;
            }
            if (url && [self showWebkitPopoverAtPoint:event.locationInWindow url:url]) {
                return;
            }
            break;
        }

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
                 externalAttributes:ea];
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
- (NSDictionary *)charAttributes:(screen_char_t)c externalAttributes:(iTermExternalAttribute *)ea {
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
        fgColor = [fgColor colorByPremultiplyingAlphaWithColor:bgColor];
    }

    int underlineStyle = (ea.urlCode || c.underline) ? (NSUnderlineStyleSingle | NSUnderlineByWord) : 0;

    BOOL isItalic = c.italic;
    PTYFontInfo *fontInfo = [self getFontForChar:c.code
                                       isComplex:c.complexChar
                                      renderBold:&isBold
                                    renderItalic:&isItalic];
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
    if (![iTermAdvancedSettingsModel copyBackgroundColor]) {
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

#pragma mark - iTermURLActionHelperDelegate

- (BOOL)urlActionHelperShouldIgnoreHardNewlines:(iTermURLActionHelper *)helper {
    return [self.delegate textViewInInteractiveApplication];
}

- (iTermImageInfo *)urlActionHelper:(iTermURLActionHelper *)helper imageInfoAt:(VT100GridCoord)coord {
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

- (VT100RemoteHost *)urlActionHelper:(iTermURLActionHelper *)helper remoteHostOnLine:(int)y {
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
    NSFont *font = self.primaryFont.font;
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
        [self setNeedsDisplay:YES];
    }
}

- (BOOL)missingImageIsVisible:(iTermImageInfo *)image {
    if (![self.drawingHelper.missingImages containsObject:image.uniqueIdentifier]) {
        return NO;
    }
    return [self imageIsVisible:image];
}

- (BOOL)imageIsVisible:(iTermImageInfo *)image {
    int firstVisibleLine = [[self enclosingScrollView] documentVisibleRect].origin.y / self.lineHeight;
    int width = [self.dataSource width];
    for (int y = 0; y < [self.dataSource height]; y++) {
        screen_char_t *theLine = [self.dataSource getLineAtIndex:y + firstVisibleLine];
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

- (VT100ScreenMark *)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
                      markOnLine:(int)line {
    return [self.dataSource markOnLine:line];
}

- (NSString *)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
   workingDirectoryOnLine:(int)line {
    return [self.dataSource workingDirectoryOnLine:line];
}

- (nullable iTermImageInfo *)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
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
    for (PTYNoteViewController *note in [self.dataSource notesInRange:coordRange]) {
        if (note.isNoteHidden) {
            return YES;
        }
    }
    return NO;
}

- (void)contextMenuRevealAnnotations:(iTermTextViewContextMenuHelper *)contextMenu at:(VT100GridCoord)coord {
    for (PTYNoteViewController *note in [self.dataSource notesInRange:VT100GridCoordRangeMake(coord.x,
                                                                                              coord.y,
                                                                                              coord.x + 1,
                                                                                              coord.y)]) {
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

- (VT100RemoteHost *)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu remoteHostOnLine:(int)line {
    return [self.dataSource remoteHostOnLine:line];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu insertText:(NSString *)text {
    [self.delegate insertText:text];
}

- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu hasOutputForCommandMark:(VT100ScreenMark *)commandMark {
    return [self.dataSource textViewRangeOfOutputForCommandMark:commandMark].start.x != -1;
}

- (VT100GridCoordRange)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
       rangeOfOutputForCommandMark:(VT100ScreenMark *)mark {
    return [self.dataSource textViewRangeOfOutputForCommandMark:mark];
}

- (void)contextMenuCopySelectionAccordingToUserPreferences:(iTermTextViewContextMenuHelper *)contextMenu {
    [self copySelectionAccordingToUserPreferences];
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
               copy:(NSString *)string {
    [self copyString:string];
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

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu saveImage:(iTermImageInfo *)imageInfo {
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

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu copyImage:(iTermImageInfo *)imageInfo {
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    NSPasteboardItem *item = imageInfo.pasteboardItem;
    if (item) {
        [pboard clearContents];
        [pboard writeObjects:@[ item ]];
    }
}


- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu openImage:(iTermImageInfo *)imageInfo {
    NSString *name = imageInfo.nameForNewSavedTempFile;
    if (name) {
        [[iTermLaunchServices sharedInstance] openFile:name];
    }
}

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu inspectImage:(iTermImageInfo *)imageInfo {
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

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu toggleAnimationOfImage:(iTermImageInfo *)imageInfo {
    if (imageInfo) {
        imageInfo.paused = !imageInfo.paused;
        if (!imageInfo.paused) {
            // A redraw is needed to recompute which visible lines are animated
            // and ensure they keep getting redrawn on a fast cadence.
            [self setNeedsDisplay:YES];
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

#pragma mark - NSResponder Additions

- (void)sendSnippet:(id)sender {
    iTermSnippet *snippet = [iTermSnippet castFrom:[sender representedObject]];
    if (!snippet) {
        return;
    }
    NSEvent *event = [NSApp currentEvent];
    const BOOL option = !!(event.modifierFlags & NSEventModifierFlagOption);
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

- (IBAction)convertMatchesToSelections:(id)sender {
    [self.selection endLiveSelection];
    [self.selection clearSelection];
    const int width = [self.dataSource width];

    NSArray<iTermSubSelection *> *subs = [self.findOnPageHelper.searchResults.array mapWithBlock:^id(SearchResult *result) {
        const VT100GridAbsWindowedRange range  = VT100GridAbsWindowedRangeMake(result.absCoordRange, 0, 0);
        iTermSubSelection *sub = [iTermSubSelection subSelectionWithAbsRange:range
                                                                        mode:kiTermSelectionModeCharacter
                                                                       width:width];
        return sub;
    }];
    if (!subs.count) {
        return;
    }
    [self.selection addSubSelections:subs];
    [self.window makeFirstResponder:self];
}

@end
