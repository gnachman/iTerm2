//
//  iTermTextViewContextMenuHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/30/20.
//

#import "iTermTextViewContextMenuHelper.h"

#import "DebugLogging.h"
#import "NSDictionary+iTerm.h"
#import "NSURL+iTerm.h"
#import "SCPPath.h"
#import "SmartSelectionController.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAPIHelper.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermContextMenuUtilities.h"
#import "iTermImageInfo.h"
#import "iTermPreferences.h"
#import "iTermScriptFunctionCall.h"
#import "iTermSelection.h"
#import "iTermTextExtractor.h"
#import "iTermURLActionHelper.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Session.h"
#import "iTermVariableScope+Tab.h"
#import "NSColor+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"
#import "URLAction.h"
#import "WindowControllerInterface.h"

const int kMaxSelectedTextLengthForCustomActions = 400;

@interface iTermTextViewContextMenuHelper()<NSMenuItemValidation>
@end

@implementation iTermTextViewContextMenuHelper

- (instancetype)initWithURLActionHelper:(iTermURLActionHelper *)urlActionHelper {
    self = [super init];
    if (self) {
        _urlActionHelper = urlActionHelper;
    }
    return self;
}

- (NSDictionary<NSNumber *, NSString *> *)smartSelectionActionSelectorDictionary {
    // The selector's name must begin with contextMenuAction to
    // pass validateMenuItem.
    return @{ @(kOpenFileContextMenuAction): NSStringFromSelector(@selector(contextMenuActionOpenFile:)),
              @(kOpenUrlContextMenuAction): NSStringFromSelector(@selector(contextMenuActionOpenURL:)),
              @(kRunCommandContextMenuAction): NSStringFromSelector(@selector(contextMenuActionRunCommand:)),
              @(kRunCoprocessContextMenuAction): NSStringFromSelector(@selector(contextMenuActionRunCoprocess:)),
              @(kSendTextContextMenuAction): NSStringFromSelector(@selector(contextMenuActionSendText:)),
              @(kRunCommandInWindowContextMenuAction): NSStringFromSelector(@selector(contextMenuActionRunCommandInWindow:)),
              @(kCopyContextMenuAction): NSStringFromSelector(@selector(contextMenuActionCopy:))
    };
}

// This method is called by control-click or by clicking the hamburger icon in the session title bar.
// Two-finger tap (or presumably right click with a mouse) would go through mouseUp->
// PointerController->openContextMenuWithEvent.
- (NSMenu *)menuForEvent:(NSEvent *)theEvent {
    if (theEvent) {
        // Control-click
        if ([iTermPreferences boolForKey:kPreferenceKeyControlLeftClickBypassesContextMenu] &&
            [self.delegate contextMenuIsMouseEventReportable:self forEvent:theEvent]) {
            return nil;
        }
        NSPoint clickPoint = [self.delegate contextMenu:self clickPoint:theEvent allowRightMarginOverflow:NO];
        _validationClickPoint = VT100GridCoordMake(clickPoint.x, clickPoint.y);

        NSMenu *menu = [self contextMenuWithEvent:theEvent];
        menu.delegate = self;
        return menu;
    }
    // Hamburger icon in session title view.
    _validationClickPoint = VT100GridCoordMake(-1, -1);
    NSMenu *menu = [self titleBarMenu];
    _savedSelectedText = [self.delegate contextMenuSelectedText:self capped:0].copy;
    menu.delegate = self;
    return menu;
}

- (void)openContextMenuAt:(VT100GridCoord)clickPoint event:(NSEvent *)event {
    _validationClickPoint = clickPoint;
    NSMenu *menu = [self contextMenuWithEvent:event];
    menu.delegate = self;
    NSView *view = [self.delegate contextMenuViewForMenu:self];
    [NSMenu popUpContextMenu:menu withEvent:event forView:view];
    _validationClickPoint = VT100GridCoordMake(-1, -1);
}

- (id<VT100ScreenMarkReading>)markForClick:(NSEvent *)event requireMargin:(BOOL)requireMargin {
    NSPoint locationInWindow = [event locationInWindow];
    if (requireMargin && locationInWindow.x >= [iTermPreferences intForKey:kPreferenceKeySideMargins]) {
        return nil;
    }
    iTermOffscreenCommandLine *offscreenCommandLine =
        [self.delegate contextMenu:self offscreenCommandLineForClickAt:event.locationInWindow];
    if (offscreenCommandLine) {
        return nil;
    }
    const NSPoint clickPoint = [self.delegate contextMenu:self
                                               clickPoint:event
                                 allowRightMarginOverflow:NO];
    const int y = clickPoint.y;
    if (requireMargin) {
        return [self.delegate contextMenu:self markOnLine:y];
    } else {
        return [self.delegate contextMenu:self markAtCoord:VT100GridCoordMake(clickPoint.x, clickPoint.y)];
    }
}

- (NSMenu *)timestampContextMenuWithEvent:(NSEvent *)event
                                 baseline:(NSTimeInterval)baseline
                              clickedTime:(NSTimeInterval)clickedTime {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];

    if (baseline != clickedTime) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Set Baseline for Relative Timestamps"
                                                      action:@selector(setTimestampBaseline:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = @(clickedTime);
        [menu addItem:item];
    }
    if (baseline != 0) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Disable Relative Timestamps"
                                                      action:@selector(setTimestampBaseline:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = @0;
        [menu addItem:item];
    }
    return menu;
}

- (void)setTimestampBaseline:(NSMenuItem *)sender {
    [self.delegate contextMenuSetTimestampBaseline:[sender.representedObject doubleValue]];
}

- (NSMenu *)contextMenuWithEvent:(NSEvent *)event {
    NSTimeInterval baseline = 0;
    NSTimeInterval clickedTime = 0;
    if ([self.delegate contextMenuClickIsOnTimestamps:event
                                      currentBaseline:&baseline
                                          clickedTime:&clickedTime]) {
        return [self timestampContextMenuWithEvent:event
                                          baseline:baseline
                                       clickedTime:clickedTime];
    }
    const NSPoint clickPoint = [self.delegate contextMenu:self
                                               clickPoint:event
                                 allowRightMarginOverflow:NO];
    const int x = clickPoint.x;
    const int y = clickPoint.y;

    const VT100GridCoord coord = VT100GridCoordMake(x, y);
    id<iTermImageInfoReading> imageInfo = [self.delegate contextMenu:self imageInfoAtCoord:coord];

    const long long overflow = [self.delegate contextMenuTotalScrollbackOverflow:self];
    iTermSelection *selection = [self.delegate contextMenuSelection:self];
    const BOOL clickedInExistingSelection = [selection containsAbsCoord:VT100GridAbsCoordMake(x, y + overflow)];
    if (!imageInfo &&
        !clickedInExistingSelection) {
        // Didn't click on selection.
        // Save the selection and do a smart selection. If we don't like the result, restore it.
        iTermSelection *savedSelection = [selection copy];
        [_urlActionHelper smartSelectWithEvent:event];
        NSCharacterSet *nonWhiteSpaceSet = [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet];
        NSString *text = [[self.delegate contextMenuSelectedText:self capped:0] copy];
        if (!text ||
            !text.length ||
            [text rangeOfCharacterFromSet:nonWhiteSpaceSet].location == NSNotFound) {
            // If all we selected was white space, undo it.
            [self.delegate contextMenu:self setSelection:savedSelection];
            _savedSelectedText = [[self.delegate contextMenuSelectedText:self capped:0] copy];
        } else {
            _savedSelectedText = text;
        }
    } else if (clickedInExistingSelection && [self.delegate contextMenuSelectionIsShort:self]) {
        _savedSelectedText = [[self.delegate contextMenuSelectedText:self capped:0] copy];
    }
    NSMenu *contextMenu = [self menuAtCoord:coord];

    id<VT100ScreenMarkReading> mark = [self.delegate contextMenu:self markOnLine:y];
    DLog(@"contextMenuWithEvent:%@ x=%d, mark=%@, mark command=%@", event, x, mark, [mark command]);
    [self addFoldUnfoldMenuItemForLine:y contextMenu:contextMenu];
    if (mark.name) {
        NSMenuItem *nameItem = [[NSMenuItem alloc] initWithTitle:mark.name action:nil keyEquivalent:@""];

        NSMenuItem *removeItem = [[NSMenuItem alloc] initWithTitle:@"Remove Named Mark" action:@selector(removeNamedMark:) keyEquivalent:@""];
        removeItem.target = self;
        removeItem.representedObject = mark;

        [contextMenu insertItem:nameItem atIndex:0];
        [contextMenu insertItem:removeItem atIndex:1];
        [contextMenu insertItem:[NSMenuItem separatorItem] atIndex:2];
    }
    if (mark && mark.command.length) {
        NSMenuItem *markItem = [[NSMenuItem alloc] initWithTitle:@"Command Info"
                                                          action:@selector(revealCommandInfo:)
                                                   keyEquivalent:@""];
        markItem.target = self;
        markItem.representedObject = mark;
        [contextMenu insertItem:markItem atIndex:0];
        [contextMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
    }
    return contextMenu;
}

- (void)addFoldUnfoldMenuItemForLine:(int)y contextMenu:(NSMenu *)contextMenu {
    id<iTermFoldMarkReading> foldMark = [self.delegate contextMenuFoldAtLine:y];
    id<VT100ScreenMarkReading> mark = [self.delegate contextMenuCommandWithOutputAtLine:y];

    if (foldMark) {
        NSMenuItem *markItem = [[NSMenuItem alloc] initWithTitle:@"Unfold"
                                                          action:@selector(unfoldMark:)
                                                   keyEquivalent:@""];
        markItem.target = self;
        markItem.representedObject = foldMark;
        [contextMenu insertItem:markItem atIndex:0];
        [contextMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
    } else if (mark && mark.command.length && [self.delegate contextMenu:self markShouldBeFoldable:mark]) {
        NSMenuItem *markItem = [[NSMenuItem alloc] initWithTitle:@"Fold"
                                                          action:@selector(foldCommandMark:)
                                                   keyEquivalent:@""];
        markItem.target = self;
        markItem.representedObject = mark;
        [contextMenu insertItem:markItem atIndex:0];
        [contextMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if ([item action] == @selector(downloadWithSCP:)) {
        if (![self.delegate contextMenuSelectionIsReasonable:self])  {
            return NO;
        }
        __block BOOL result = NO;
        iTermSelection *selection = [self.delegate contextMenuSelection:self];
        const BOOL valid =
        [self.delegate contextMenu:self withRelativeCoord:selection.lastAbsRange.coordRange.start block:^(VT100GridCoord coord) {
            const BOOL haveShortSelection = [self.delegate contextMenuSelectionIsShort:self];
            NSString *selectedText = [self.delegate contextMenuSelectedText:self capped:0];
            result = (haveShortSelection &&
                      [selection hasSelection] &&
                      [self.delegate contextMenu:self scpPathForFile:selectedText onLine:coord.y] != nil);
        }];
        return (valid && result);
    }
    if ([item action] == @selector(restartSession:)) {
        return [self.delegate contextMenuSessionCanBeRestarted:self];
    }
    if ([item action] == @selector(toggleBroadcastingInput:) ||
        [item action] == @selector(closeTextViewSession:) ||
        [item action] == @selector(editTextViewSession:) ||
        [item action] == @selector(clearTextViewBuffer:) ||
        [item action] == @selector(splitTextViewVertically:) ||
        [item action] == @selector(splitTextViewHorizontally:) ||
        [item action] == @selector(movePane:) ||
        [item action] == @selector(swapSessions:) ||
        [item action] == @selector(reRunCommand:) ||
        [item action] == @selector(saveImageAs:) ||
        [item action] == @selector(copyImage:) ||
        [item action] == @selector(openImage:) ||
        [item action] == @selector(togglePauseAnimatingImage:) ||
        [item action] == @selector(inspectImage:) ||
        [item action] == @selector(apiMenuItem:) ||
        [item action] == @selector(copyLinkAddress:) ||
        [item action] == @selector(copyString:) ||
        [item action] == @selector(copyData:) ||
        [item action] == @selector(replaceWithPrettyJSON:) ||
        [item action] == @selector(replaceWithBase64Decoded:) ||
        [item action] == @selector(replaceWithBase64Encoded:) ||
        [item action] == @selector(revealCommandInfo:) ||
        [item action] == @selector(removeNamedMark:)) {
        return YES;
    }
    if ([item action] == @selector(stopCoprocess:)) {
        return [self.delegate contextMenuHasCoprocess:self];
    }
    if ([item action] == @selector(bury:)) {
        return [self.delegate contextMenuCanBurySession:self];
    }
    if ([item action] == @selector(selectCommandOutput:)) {
        id<VT100ScreenMarkReading> commandMark = [item representedObject];
        return [self.delegate contextMenu:self hasOutputForCommandMark:commandMark];
    }
    if ([item action] == @selector(sendSelection:) ||
        [item action] == @selector(addNote:) ||
        [item action] == @selector(mail:) ||
        [item action] == @selector(browse:) ||
        [item action] == @selector(quickLook:) ||
        [item action] == @selector(searchInBrowser:) ||
        [item action] == @selector(addTrigger:) ||
        [item action] == @selector(saveSelectionAsSnippet:)) {
        iTermSelection *selection = [self.delegate contextMenuSelection:self];
        return selection.hasSelection;
    }

    if ([item action] == @selector(showNotes:)) {
        if (self.validationClickPoint.x < 0) {
            return NO;
        }
        const VT100GridCoordRange range = VT100GridCoordRangeMake(_validationClickPoint.x,
                                                                  _validationClickPoint.y,
                                                                  _validationClickPoint.x + 1,
                                                                  _validationClickPoint.y);
        return [self.delegate contextMenu:self hasOpenAnnotationInRange:range];
    }
    if (item.action == @selector(foldCommandMark:) || item.action == @selector(unfoldMark:)) {
        return YES;
    }
    if (item.action == @selector(setTimestampBaseline:)) {
        return YES;
    }
    if ([self.smartSelectionActionSelectorDictionary.allValues containsObject:NSStringFromSelector(item.action)]) {
        return YES;
    }

    return NO;
}

#pragma mark - Private


- (NSMenu *)menuAtCoord:(VT100GridCoord)coord {
    NSMenu *theMenu;

    // Allocate a menu
    theMenu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];
    id<iTermImageInfoReading> imageInfo = [self.delegate contextMenu:self imageInfoAtCoord:coord];
    if (imageInfo) {
        // Show context menu for an image.
        NSArray *entryDicts;
        if (imageInfo.broken) {
            entryDicts =
                @[ @{ @"title": @"Save File As…",
                      @"selector": NSStringFromSelector(@selector(saveImageAs:)) },
                   @{ @"title": @"Copy File",
                      @"selector": NSStringFromSelector(@selector(copyImage:)) },
                   @{ @"title": @"Open File",
                      @"selector": NSStringFromSelector(@selector(openImage:)) },
                   @{ @"title": @"Inspect",
                      @"selector": NSStringFromSelector(@selector(inspectImage:)) } ];
        } else {
            entryDicts =
                @[ @{ @"title": @"Save Image As…",
                      @"selector": NSStringFromSelector(@selector(saveImageAs:)) },
                   @{ @"title": @"Copy Image",
                      @"selector": NSStringFromSelector(@selector(copyImage:)) },
                   @{ @"title": @"Open Image",
                      @"selector": NSStringFromSelector(@selector(openImage:)) },
                   @{ @"title": @"Inspect",
                      @"selector": NSStringFromSelector(@selector(inspectImage:)) } ];
        }
        if (imageInfo.animated || imageInfo.paused) {
            NSString *selector = NSStringFromSelector(@selector(togglePauseAnimatingImage:));
            if (imageInfo.paused) {
                entryDicts = [entryDicts arrayByAddingObject:@{ @"title": @"Resume Animating",
                                                                @"selector": selector }];
            } else {
                entryDicts = [entryDicts arrayByAddingObject:@{ @"title": @"Stop Animating",
                                                                @"selector": selector }];
            }
        }
        for (NSDictionary *entryDict in entryDicts) {
            NSMenuItem *item;

            item = [[NSMenuItem alloc] initWithTitle:entryDict[@"title"]
                                              action:NSSelectorFromString(entryDict[@"selector"])
                                       keyEquivalent:@""];
            [item setRepresentedObject:imageInfo];
            item.target = self;
            [theMenu addItem:item];
        }
        return theMenu;
    }

    const BOOL haveShortSelection = [self.delegate contextMenuSelectionIsShort:self];
    NSString *shortSelectedText = nil;
    {
        BOOL needSeparator = NO;
        if (haveShortSelection) {
            shortSelectedText = [self.delegate contextMenuSelectedText:self capped:0];
            NSArray<iTermTuple<NSString *, NSString *> *> *synonyms = [shortSelectedText helpfulSynonyms];
            needSeparator = synonyms.count > 0;
            for (iTermTuple<NSString *, NSString *> *tuple in synonyms) {
                NSMenuItem *theItem = [[NSMenuItem alloc] init];
                theItem.title = tuple.firstObject;
                theItem.representedObject = tuple.secondObject;
                theItem.target = self;
                theItem.action = @selector(copyString:);
                [theMenu addItem:theItem];
            }
            if ([iTermContextMenuUtilities addMenuItemForColors:shortSelectedText menu:theMenu index:theMenu.itemArray.count]) {
                needSeparator = YES;
            }
            const NSInteger initialCount = theMenu.itemArray.count;
            if ([iTermContextMenuUtilities addMenuItemForBase64Encoded:shortSelectedText menu:theMenu index:theMenu.itemArray.count selector:@selector(copyData:) target:nil] > initialCount) {
                needSeparator = YES;
            }
        }
        if ([self.delegate contextMenuSelectionIsReasonable:self]) {
            NSString *text = [self.delegate contextMenuSelectedText:self capped:0];
            NSInteger initialCount = theMenu.itemArray.count;
            [iTermContextMenuUtilities addMenuItemsForNumericConversions:text menu:theMenu index:theMenu.itemArray.count selector:@selector(copyString:) target:nil];

            NSString *unstrippedSelectedText = [self.delegate contextMenuUnstrippedSelectedText:self capped:0];
            if ([iTermContextMenuUtilities addMenuItemsToCopyBase64:unstrippedSelectedText
                                                               menu:theMenu
                                                              index:theMenu.itemArray.count
                                                  selectorForString:@selector(copyString:)
                                                    selectorForData:@selector(copyData:)
                                                             target:self] > initialCount) {
                needSeparator = YES;
            }

            NSArray<iTermSelectionReplacement *> *replacements = [self.delegate contextMenuSelectionReplacements:self];
            if (replacements.count > 0){
                [theMenu addItem:[NSMenuItem separatorItem]];
            }
            for (iTermSelectionReplacement *replacement in replacements) {
                NSMenuItem *item = [[NSMenuItem alloc] init];
                item.target = self;
                item.representedObject = replacement;
                [theMenu addItem:item];
                needSeparator = YES;

                switch (replacement.kind) {
                    case iTermSelectionReplacementKindJson:
                        item.title = @"Replace with Pretty-Printed JSON";
                        item.action = @selector(replaceWithPrettyJSON:);
                        break;

                    case iTermSelectionReplacementKindBase64Decode:
                        item.title = @"Replace with Base64-Decoded Value";
                        item.action = @selector(replaceWithBase64Decoded:);
                        break;

                    case iTermSelectionReplacementKindBase64Encode:
                        item.title = @"Replace with Base64-Encoded Value";
                        item.action = @selector(replaceWithBase64Encoded:);
                        break;
                }
            }
        }
        if (needSeparator) {
            [theMenu addItem:[NSMenuItem separatorItem]];
        }
    }
    iTermSelection *selection = [self.delegate contextMenuSelection:self];
    if (selection.length == 1) {
        iTermSubSelection *sub = selection.allSubSelections.firstObject;
        [self.delegate contextMenu:self withRelativeCoord:sub.absRange.coordRange.start block:^(VT100GridCoord coord) {
            iTermTextExtractor *extractor = [self.delegate contextMenuTextExtractor:self];
            const screen_char_t c = [extractor characterAt:coord];
            NSString *description = ScreenCharDescription(c);
            if (description) {
                iTermExternalAttribute *ea = [extractor externalAttributesAt:coord];
                if (ea) {
                    description = [NSString stringWithFormat:@"%@; %@", description, [ea humanReadableDescription]];
                }
                NSMenuItem *theItem = [[NSMenuItem alloc] init];
                theItem.title = description;
                [theMenu addItem:theItem];
            }
        }];
    }

    // Menu items for acting on text selections
    __block NSString *scpTitle = @"Download with scp";
    if (haveShortSelection) {
        [self.delegate contextMenu:self withRelativeCoord:selection.lastAbsRange.coordRange.start block:^(VT100GridCoord coord) {
            SCPPath *scpPath = [self.delegate contextMenu:self scpPathForFile:shortSelectedText onLine:coord.y];
            if (scpPath) {
                scpTitle = [NSString stringWithFormat:@"Download with scp from %@", scpPath.hostname];
            }
        }];
    }

    void (^add)(NSString *, SEL) = ^(NSString *title, SEL selector) {
        [theMenu addItemWithTitle:title
                         action:selector
                    keyEquivalent:@""];
        [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];
    };
    add(scpTitle, @selector(downloadWithSCP:));
    add(@"Open Selection as URL", @selector(browse:));
    if (shortSelectedText && [self.delegate contextMenu:self canQuickLookURL:[NSURL URLWithUserSuppliedString:shortSelectedText]]) {
        add(@"Quick Look Link", @selector(quickLook:));
    }
    add(@"Search the Web for Selection", @selector(searchInBrowser:));

    add(@"Send Email to Selected Address", @selector(mail:));
    add(@"Add Trigger…", @selector(addTrigger:));

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Custom actions
    if ([selection hasSelection] &&
        [selection length] < kMaxSelectedTextLengthForCustomActions &&
        coord.y >= 0) {
        NSString *selectedText = [self.delegate contextMenuSelectedText:self capped:1024];
        if ([self addCustomActionsToMenu:theMenu matchingText:selectedText line:coord.y]) {
            [theMenu addItem:[NSMenuItem separatorItem]];
        }
    }

    if ([self addAPIProvidedMenuItems:theMenu]) {
        [theMenu addItem:[NSMenuItem separatorItem]];
    }

    // Split pane options
    add(@"Split Pane Vertically", @selector(splitTextViewVertically:));
    add(@"Split Pane Horizontally", @selector(splitTextViewHorizontally:));

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    add(@"Move Session to Split Pane", @selector(movePane:));
    if ([self.delegate contextMenuCurrentTabHasMultipleSessions:self]) {
        NSMenuItem *item = [theMenu addItemWithTitle:@"Move Session to Tab"
                                              action:@selector(moveSessionToTab:)
                                       keyEquivalent:@""];
        item.representedObject = [self.delegate contextMenuSessionScope:self].ID;
    }
    [theMenu addItemWithTitle:@"Move Session to Window"
                     action:@selector(moveSessionToWindow:)
                keyEquivalent:@""];
    add(@"Swap With Session…", @selector(swapSessions:));

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Copy,  paste, and save
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Copy",
                                                                 @"iTerm",
                                                                 [NSBundle bundleForClass: [self class]],
                                                                 @"Context menu")
                     action:@selector(copy:) keyEquivalent:@""];

    // Don't attempt to extract a URL from invalid coordinates (-1,-1) if opened from the session titlebar
    if (coord.x >= 0 && coord.y >= 0) {
        iTermTextExtractor *extractor = [self.delegate contextMenuTextExtractor:self];
        NSString *urlID;
        NSURL *url = [extractor urlOfHypertextLinkAt:coord urlId:&urlID];
        if (url) {
            NSMenuItem *item = [theMenu addItemWithTitle:@"Copy Link Address" action:@selector(copyLinkAddress:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = url;
        }
    }
    
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Paste",
                                                                 @"iTerm",
                                                                 [NSBundle bundleForClass: [self class]],
                                                                 @"Context menu")
                     action:@selector(paste:) keyEquivalent:@""];
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Save",
                                                                 @"iTerm",
                                                                 [NSBundle bundleForClass: [self class]],
                                                                 @"Context menu")
                     action:@selector(saveDocumentAs:) keyEquivalent:@""];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Select all
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Select All",
                                                                 @"iTerm",
                                                                 [NSBundle bundleForClass: [self class]],
                                                                 @"Context menu")
                     action:@selector(selectAll:) keyEquivalent:@""];

    add(@"Send Selection", @selector(sendSelection:));
    add(@"Save Selection as Snippet", @selector(saveSelectionAsSnippet:));

    // Clear buffer
    add(@"Clear Buffer", @selector(clearTextViewBuffer:));

    // Make note
    add(@"Annotate Selection", @selector(addNote:));
    add(@"Reveal Annotation", @selector(showNotes:));

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Edit Session
    add(@"Edit Session...", @selector(editTextViewSession:));

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Toggle broadcast
    add(@"Toggle Broadcasting Input", @selector(toggleBroadcastingInput:));

    if ([self.delegate contextMenuHasCoprocess:self]) {
        add(@"Stop Coprocess", @selector(stopCoprocess:));
    }

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Close current pane
    add(@"Close", @selector(closeTextViewSession:));
    add(@"Restart", @selector(restartSession:));

    [self.delegate contextMenu:self amend:theMenu];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];
    add(@"Bury", @selector(bury:));

    // Terminal State
    [theMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *terminalState = [[NSMenuItem alloc] initWithTitle:@"Terminal State" action:nil keyEquivalent:@""];
    terminalState.submenu = [[NSMenu alloc] initWithTitle:@"Terminal State"];

    struct {
        NSString *title;
        SEL action;
    } terminalStateDecls[] = {
        { @"Alternate Screen", @selector(terminalStateToggleAlternateScreen:) },
        { nil, nil },
        { @"Focus Reporting", @selector(terminalStateToggleFocusReporting:) },
        { @"Mouse Reporting", @selector(terminalStateToggleMouseReporting:) },
        { @"Paste Bracketing", @selector(terminalStateTogglePasteBracketing:) },
        { nil, nil },
        { @"Application Cursor", @selector(terminalStateToggleApplicationCursor:) },
        { @"Application Keypad", @selector(terminalStateToggleApplicationKeypad:) },
        { nil, nil },
        { @"Standard Key Reporting Mode", @selector(terminalToggleKeyboardMode:) },
        { @"modifyOtherKeys Mode 1", @selector(terminalToggleKeyboardMode:) },
        { @"modifyOtherKeys Mode 2", @selector(terminalToggleKeyboardMode:) },
        { @"CSI u Mode", @selector(terminalToggleKeyboardMode:) },
        { @"Raw Key Reporting Mode", @selector(terminalToggleKeyboardMode:) },
        { nil, nil },
        { @"Disambiguate Escape", @selector(terminalToggleKeyboardMode:) },
        { @"Report All Event Types", @selector(terminalToggleKeyboardMode:) },
        { @"Report Alternate Keys", @selector(terminalToggleKeyboardMode:) },
        { @"Report All Keys as Escape Codes", @selector(terminalToggleKeyboardMode:) },
        { @"Report Associated Text", @selector(terminalToggleKeyboardMode:) },
        { nil, nil },
        { @"Literal Controls", @selector(terminalStateToggleLiteralMode:)},
        { nil, nil },
        { @"Emulation Level", nil }
    };
    NSInteger j = 1;
    for (size_t i = 0; i < sizeof(terminalStateDecls) / sizeof(*terminalStateDecls); i++) {
        if (!terminalStateDecls[i].title) {
            [terminalState.submenu addItem:[NSMenuItem separatorItem]];
            continue;
        }
        NSMenuItem *item = [terminalState.submenu addItemWithTitle:terminalStateDecls[i].title
                                                            action:terminalStateDecls[i].action
                                                     keyEquivalent:@""];
        item.tag = j;
        j += 1;
        item.state = [self.delegate contextMenu:self terminalStateForMenuItem:item];
    }

    NSMenuItem *levelItem = terminalState.submenu.itemArray.lastObject;
    NSMenu *levelMenu = [[NSMenu alloc] init];
    levelItem.submenu = levelMenu;

    struct {
        NSString *title;
        SEL action;
    } emulationLevelDecls[] = {
        { @"VT100", @selector(terminalStateSetEmulationLevel:) },
        { @"VT200", @selector(terminalStateSetEmulationLevel:) },
        { @"VT300", @selector(terminalStateSetEmulationLevel:) },
        { @"VT400", @selector(terminalStateSetEmulationLevel:) },
        { @"VT500", @selector(terminalStateSetEmulationLevel:) },
    };
    j = 100;
    for (size_t i = 0; i < sizeof(emulationLevelDecls) / sizeof(*emulationLevelDecls); i++) {
        if (!emulationLevelDecls[i].title) {
            [levelMenu addItem:[NSMenuItem separatorItem]];
            continue;
        }
        NSMenuItem *item = [levelMenu addItemWithTitle:emulationLevelDecls[i].title
                                                action:emulationLevelDecls[i].action
                                         keyEquivalent:@""];
        item.tag = j;
        j += 100;
        item.state = [self.delegate contextMenu:self terminalStateForMenuItem:item];
    }

    [theMenu addItem:terminalState];

    [self.delegate contextMenu:self addContextMenuItems:theMenu];

    [self addMainMenuIfNeededTo:theMenu];

    return theMenu;
}

- (void)addMainMenuIfNeededTo:(NSMenu *)menu {
    if (![[iTermApplication sharedApplication] isUIElement]) {
        return;
    }
    NSMenuItem *mainMenuItem = [[NSMenuItem alloc] initWithTitle:@"Main Menu" action:nil keyEquivalent:@""];
    NSMenu *copyOfMainMenu = [[NSMenu alloc] init];
    for (NSMenuItem *mainMenuItem in NSApp.mainMenu.itemArray) {
        [self addCopyOfItem:mainMenuItem to:copyOfMainMenu];
    }
    mainMenuItem.submenu = copyOfMainMenu;
    [menu insertItem:mainMenuItem atIndex:0];
    [menu insertItem:[NSMenuItem separatorItem] atIndex:1];
}

- (void)addCopyOfItem:(NSMenuItem *)item to:(NSMenu *)menu {
    [menu addItem:[item copy]];
}

- (SEL)selectorForSmartSelectionAction:(NSDictionary *)action {
    NSDictionary<NSNumber *, NSString *> *dictionary = [self smartSelectionActionSelectorDictionary];
    ContextMenuActions contextMenuAction = [ContextMenuActionPrefsController actionForActionDict:action];
    return NSSelectorFromString(dictionary[@(contextMenuAction)]);
}

- (BOOL)addCustomActionsToMenu:(NSMenu *)theMenu matchingText:(NSString *)textWindow line:(int)line {
    BOOL didAdd = NO;
    NSArray *rulesArray = [self.delegate contextMenuSmartSelectionRules:self] ?: [SmartSelectionController defaultRules];
    const int numRules = [rulesArray count];

    DLog(@"Looking for custom actions. Evaluating smart selection rules…");
    DLog(@"text window is: %@", textWindow);
    for (int j = 0; j < numRules; j++) {
        NSDictionary *rule = [rulesArray objectAtIndex:j];
        NSArray *actions = [SmartSelectionController actionsInRule:rule];
        if (!actions.count) {
            DLog(@"Skipping rule with no actions:\n%@", rule);
            continue;
        }

        DLog(@"Evaluating rule:\n%@", rule);
        NSString *regex = [SmartSelectionController regexInRule:rule];
        for (int i = 0; i <= textWindow.length; i++) {
            NSString *substring = [textWindow substringWithRange:NSMakeRange(i, [textWindow length] - i)];
            NSError *regexError = nil;
            NSArray *components = [substring captureComponentsMatchedByRegex:regex
                                                                     options:0
                                                                       range:NSMakeRange(0, [substring length])
                                                                       error:&regexError];
            if (components.count) {
                DLog(@"Components for %@ are %@", regex, components);
                for (NSDictionary *action in actions) {
                    SEL mySelector = [self selectorForSmartSelectionAction:action];
                    NSString *workingDirectory = [self.delegate contextMenu:self workingDirectoryOnLine:line];
                    id<VT100RemoteHostReading> remoteHost = [self.delegate contextMenu:self remoteHostOnLine:line];
                    NSString *theTitle =
                        [ContextMenuActionPrefsController titleForActionDict:action
                                                       withCaptureComponents:components
                                                            workingDirectory:workingDirectory
                                                                  remoteHost:remoteHost];

                    NSMenuItem *theItem = [[NSMenuItem alloc] initWithTitle:theTitle
                                                                     action:mySelector
                                                              keyEquivalent:@""];
                    NSDictionary *dict = [@{ iTermSmartSelectionActionContextKeyAction: action,
                                             iTermSmartSelectionActionContextKeyComponents: components,
                                             iTermSmartSelectionActionContextKeyWorkingDirectory: workingDirectory ?: [NSNull null],
                                             iTermSmartSelectionActionContextKeyRemoteHost: (id)remoteHost ?: (id)[NSNull null]} dictionaryByRemovingNullValues];
                    [theItem setRepresentedObject:dict];
                    [theItem setTarget:self];
                    [theMenu addItem:theItem];
                    didAdd = YES;
                }
                break;
            }
        }
    }
    return didAdd;
}

- (BOOL)addAPIProvidedMenuItems:(NSMenu *)theMenu {
    NSArray<ITMRPCRegistrationRequest *> *reqs = [iTermAPIHelper contextMenuProviderRegistrationRequests];
    if (reqs.count == 0) {
        return NO;
    }
    [theMenu addItem:[NSMenuItem separatorItem]];
    for (ITMRPCRegistrationRequest *req in reqs) {
        NSMenuItem *theItem = [[NSMenuItem alloc] initWithTitle:req.contextMenuAttributes.displayName
                                                         action:@selector(apiMenuItem:)
                                                  keyEquivalent:@""];
        theItem.representedObject = req.contextMenuAttributes.uniqueIdentifier;
        theItem.target = self;
        [theMenu addItem:theItem];
    }
    return YES;
}

- (NSMenu *)menuForMark:(id<VT100ScreenMarkReading>)mark directory:(NSString *)directory {
    NSMenu *theMenu;

    // Allocate a menu
    theMenu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];

    NSMenuItem *theItem = [[NSMenuItem alloc] init];
    theItem.title = [NSString stringWithFormat:@"Command: %@", mark.command];
    [theMenu addItem:theItem];

    if (directory) {
        theItem = [[NSMenuItem alloc] init];
        theItem.title = [NSString stringWithFormat:@"Directory: %@", directory];
        [theMenu addItem:theItem];
    }

    theItem = [[NSMenuItem alloc] init];
    theItem.title = [NSString stringWithFormat:@"Return code: %d", mark.code];
    [theMenu addItem:theItem];

    if (mark.startDate) {
        theItem = [[NSMenuItem alloc] init];
        NSTimeInterval runningTime;
        if (mark.endDate) {
            runningTime = [mark.endDate timeIntervalSinceDate:mark.startDate];
        } else {
            runningTime = -[mark.startDate timeIntervalSinceNow];
        }
        int hours = runningTime / 3600;
        int minutes = ((int)runningTime % 3600) / 60;
        int seconds = (int)runningTime % 60;
        int millis = (int) ((runningTime - floor(runningTime)) * 1000);
        if (hours > 0) {
            theItem.title = [NSString stringWithFormat:@"Running time: %d:%02d:%02d",
                             hours, minutes, seconds];
        } else {
            theItem.title = [NSString stringWithFormat:@"Running time: %d:%02d.%03d",
                             minutes, seconds, millis];
        }
        [theMenu addItem:theItem];
    }

    [theMenu addItem:[NSMenuItem separatorItem]];

    theItem = [[NSMenuItem alloc] initWithTitle:@"Re-run Command"
                                         action:@selector(reRunCommand:)
                                  keyEquivalent:@""];
    theItem.target = self;
    [theItem setRepresentedObject:mark.command];
    [theMenu addItem:theItem];

    theItem = [[NSMenuItem alloc] initWithTitle:@"Select Command Output"
                                         action:@selector(selectCommandOutput:)
                                  keyEquivalent:@""];
    theItem.target = self;
    [theItem setRepresentedObject:mark];
    [theMenu addItem:theItem];

    return theMenu;
}

#pragma mark - Context Menu Actions

- (void)foldCommandMark:(NSMenuItem *)sender {
    [self.delegate contextMenuFoldMark:sender.representedObject];
}

- (void)unfoldMark:(NSMenuItem *)sender {
    [self.delegate contextMenuUnfoldMark:sender.representedObject];
}

- (void)removeNamedMark:(id)sender {
    id<VT100ScreenMarkReading> mark = [sender representedObject];
    DLog(@"Remove named mark %@", mark);
    if (mark.name) {
        [_delegate contextMenu:self removeNamedMark:mark];
    }
}

- (void)revealCommandInfo:(id)sender {
    id<VT100ScreenMarkReading> mark = [sender representedObject];
    DLog(@"Reveal command info %@", mark);
    if (!mark || ![mark conformsToProtocol:@protocol(VT100ScreenMarkReading)]) {
        DLog(@"Bogus");
        return;
    }
    [_delegate contextMenu:self showCommandInfoForMark:mark];
}

- (void)contextMenuActionOpenFile:(id)sender {
    DLog(@"Open file: '%@'", [sender representedObject]);
    NSDictionary *dict = [sender representedObject];
    [self evaluateCustomActionDictionary:dict completion:^(NSString *value) {
        if (!value) {
            return;
        }
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:[value stringByExpandingTildeInPath]]];
    }];
}

- (void)contextMenuActionOpenURL:(id)sender {
    [self evaluateCustomActionDictionary:[sender representedObject] completion:^(NSString *value) {
        if (!value) {
            return;
        }
        NSURL *url = [NSURL URLWithUserSuppliedString:value];
        if (url) {
            DLog(@"Open URL: %@", [sender representedObject]);
            [[NSWorkspace sharedWorkspace] openURL:url];
        } else {
            DLog(@"%@ is not a URL", [sender representedObject]);
        }
    }];
}

- (void)contextMenuActionRunCommand:(id)sender {
    [self evaluateCustomActionDictionary:[sender representedObject] completion:^(NSString *value) {
        DLog(@"Run command: %@", value);
        if (!value) {
            return;
        }
        [self runCommand:value];
    }];
}

- (void)contextMenuActionRunCommandInWindow:(id)sender {
    [self evaluateCustomActionDictionary:[sender representedObject] completion:^(NSString *value) {
        DLog(@"Run command: %@", value);
        if (!value) {
            return;
        }
        [self.delegate contextMenu:self runCommandInWindow:value];
    }];
}

- (void)contextMenuActionCopy:(id)sender {
    DLog(@"Copy");
    URLAction *action = [URLAction castFrom:sender];
    if (!action) {
        DLog(@"Sender not an action or nil: %@", sender);
        return;
    }
    const VT100GridWindowedRange range = action.visualRange;
    [self.delegate contextMenu:self copyRangeAccordingToUserPreferences:range];
}

- (void)runCommand:(NSString *)command {
    [self.delegate contextMenu:self runCommandInBackground:command];
}

- (void)contextMenuActionRunCoprocess:(id)sender {
    [self evaluateCustomActionDictionary:[sender representedObject] completion:^(NSString *value) {
        DLog(@"Run coprocess: %@", value);
        if (!value) {
            return;
        }
        [self.delegate contextMenu:self runCoprocess:value];
    }];
}

- (void)contextMenuActionSendText:(id)sender {
    [self evaluateCustomActionDictionary:[sender representedObject] completion:^(NSString *value) {
        DLog(@"Send text: %@", value);
        if (!value) {
            return;
        }
        [self.delegate contextMenu:self insertText:value];
    }];
}

- (BOOL)smartSelectionActionsShouldUseInterpolatedStrings {
    return [self.delegate contextMenuSmartSelectionActionsShouldUseInterpolatedStrings:self];
}

- (void)evaluateCustomActionDictionary:(NSDictionary *)dict completion:(void (^)(NSString * _Nullable))completion {
    NSDictionary *action = dict[iTermSmartSelectionActionContextKeyAction];
    NSArray *components = dict[iTermSmartSelectionActionContextKeyComponents];
    NSString *workingDirectory = [dict[iTermSmartSelectionActionContextKeyWorkingDirectory] nilIfNull];
    id<VT100RemoteHostReading> remoteHost = [dict[iTermSmartSelectionActionContextKeyRemoteHost] nilIfNull];

    iTermVariableScope *myScope = [[self.delegate contextMenuSessionScope:self] copy];
    [myScope setValue:workingDirectory forVariableNamed:iTermVariableKeySessionPath];
    [myScope setValue:remoteHost.hostname forVariableNamed:iTermVariableKeySessionHostname];
    [myScope setValue:remoteHost.username forVariableNamed:iTermVariableKeySessionUsername];
    [ContextMenuActionPrefsController computeParameterForActionDict:action
                                              withCaptureComponents:components
                                                   useInterpolation:[self smartSelectionActionsShouldUseInterpolatedStrings]
                                                              scope:myScope
                                                              owner:[self.delegate contextMenuOwner:self]
                                                         completion:completion];
}

- (void)downloadWithSCP:(id)sender {
    iTermSelection *selection = [self.delegate contextMenuSelection:self];
    if (![selection hasSelection]) {
        return;
    }
    NSString *selectedText = [[self.delegate contextMenuSelectedText:self capped:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *parts = [selectedText componentsSeparatedByString:@"\n"];
    if (parts.count != 1) {
        return;
    }
    [self.delegate contextMenu:self
        withRelativeCoordRange:selection.lastAbsRange.coordRange
                         block:^(VT100GridCoordRange coordRange) {
        SCPPath *scpPath = [self.delegate contextMenu:self scpPathForFile:parts[0] onLine:coordRange.start.y];
        [_urlActionHelper downloadFileAtSecureCopyPath:scpPath displayName:selectedText locationInView:coordRange];
    }];
}

- (void)browse:(id)sender {
    [_urlActionHelper findUrlInString:[self.delegate contextMenuSelectedText:self capped:0] andOpenInBackground:NO];
}

- (void)quickLook:(id)sender {
    NSString *string = [self.delegate contextMenuSelectedText:self capped:0];
    NSURL *url = [NSURL URLWithUserSuppliedString:string];
    if (!url) {
        return;
    }
    [self.delegate contextMenuHandleQuickLook:self
                                          url:url
                             windowCoordinate:NSApp.currentEvent.locationInWindow];
}

- (void)searchInBrowser:(id)sender {
    NSURL *url = [NSURL urlByReplacingFormatSpecifier:@"%@"
                                             inString:[iTermAdvancedSettingsModel searchCommand]
                                            withValue:[self.delegate contextMenuSelectedText:self capped:0]];
    [_urlActionHelper findUrlInString:url.absoluteString andOpenInBackground:NO];
}

- (void)addTrigger:(id)sender {
    [self.delegate contextMenu:self addTrigger:[self.delegate contextMenuSelectedText:self capped:0]];
}

- (void)mail:(id)sender {
    NSString *mailto;

    NSString *selectedText = [self.delegate contextMenuSelectedText:self capped:0];
    if ([selectedText hasPrefix:@"mailto:"]) {
        mailto = [selectedText copy];
    } else {
        mailto = [NSString stringWithFormat:@"mailto:%@", selectedText];
    }

    NSURL *url = [NSURL URLWithUserSuppliedString:mailto];
    [self.delegate contextMenu:self openURL:url];
}

- (void)splitTextViewVertically:(id)sender {
    [self.delegate contextMenuSplitVertically:self];
}

- (void)splitTextViewHorizontally:(id)sender {
    [self.delegate contextMenuSplitHorizontally:self];
}

- (void)movePane:(id)sender {
    [self.delegate contextMenuMovePane:self];
}

- (void)copyLinkAddress:(id)sender {
    [self.delegate contextMenu:self copyURL:[sender representedObject]];
}

- (void)copyString:(id)sender {
    NSMenuItem *item = sender;
    [self.delegate contextMenu:self copy:item.representedObject];
}

- (void)copyData:(id)sender {
    NSMenuItem *item = sender;
    [self.delegate contextMenu:self copy:item.representedObject];
}

- (void)replaceWithPrettyJSON:(id)sender {
    NSMenuItem *item = sender;
    [self.delegate contextMenu:self replaceSelectionWith:item.representedObject];
}

- (void)replaceWithBase64Decoded:(id)sender {
    NSMenuItem *item = sender;
    [self.delegate contextMenu:self replaceSelectionWith:item.representedObject];
}

- (void)replaceWithBase64Encoded:(id)sender {
    NSMenuItem *item = sender;
    [self.delegate contextMenu:self replaceSelectionWith:item.representedObject];
}

- (void)swapSessions:(id)sender {
    [self.delegate contextMenuSwapSessions:self];
}

- (void)sendSelection:(id)sender {
    iTermSelection *selection = [self.delegate contextMenuSelection:self];
    if (!selection.hasSelection) {
        return;
    }
    [self.delegate contextMenuSendSelectedText:self];
}

- (void)saveSelectionAsSnippet:(id)sender {
    iTermSelection *selection = [self.delegate contextMenuSelection:self];
    if (!selection.hasSelection) {
        return;
    }
    [self.delegate contextMenuSaveSelectionAsSnippet:self];
}

- (void)clearTextViewBuffer:(id)sender {
    [self.delegate contextMenuClearBuffer:self];
}

- (void)addNote:(id)sender {
    [self.delegate contextMenuAddAnnotation:self];
}

- (void)showNotes:(id)sender {
    [self.delegate contextMenuRevealAnnotations:self at:_validationClickPoint];
}

- (void)editTextViewSession:(id)sender {
    [self.delegate contextMenuEditSession:self];
}

- (void)toggleBroadcastingInput:(id)sender {
    [self.delegate contextMenuToggleBroadcastingInput:self];
}

- (void)stopCoprocess:(id)sender {
    [self.delegate contextMenuStopCoprocess:self];
}

- (void)closeTextViewSession:(id)sender {
    [self.delegate contextMenuCloseSession:self];
}

- (void)restartSession:(id)sender {
    DLog(@"restartSession");
    [self.delegate contextMenuRestartSession:self];
}

- (void)bury:(id)sender {
    [self.delegate contextMenuBurySession:self];
}

- (void)reRunCommand:(id)sender {
    NSString *command = [sender representedObject];
    [self.delegate contextMenu:self insertText:[command stringByAppendingString:@"\n"]];
}

- (void)selectCommandOutput:(id)sender {
    id<VT100ScreenMarkReading> mark = [sender representedObject];
    [self selectOutputOfCommandMark:mark];
}

- (void)selectOutputOfCommandMark:(id<VT100ScreenMarkReading>)mark {
    VT100GridCoordRange range = [self.delegate contextMenu:self rangeOfOutputForCommandMark:mark];
    if (range.start.x == -1) {
        DLog(@"Beep: can't select output");
        NSBeep();
        return;
    }
    const long long overflow = [self.delegate contextMenuTotalScrollbackOverflow:self];
    VT100GridAbsCoordRange absRange = VT100GridAbsCoordRangeFromCoordRange(range, overflow);
    iTermSelection *selection = [self.delegate contextMenuSelection:self];
    [selection beginSelectionAtAbsCoord:absRange.start
                                    mode:kiTermSelectionModeCharacter
                                  resume:NO
                                  append:NO];
    [selection moveSelectionEndpointTo:absRange.end];
    [selection endLiveSelection];

    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self.delegate contextMenuCopySelectionAccordingToUserPreferences:self];
    }
}

- (void)saveImageAs:(NSMenuItem *)item {
    [self.delegate contextMenu:self saveImage:item.representedObject];
}

- (void)copyImage:(NSMenuItem *)item {
    [self.delegate contextMenu:self copyImage:item.representedObject];
}

- (void)openImage:(NSMenuItem *)item {
    [self.delegate contextMenu:self openImage:item.representedObject];
}

- (void)inspectImage:(NSMenuItem *)item {
    [self.delegate contextMenu:self inspectImage:item.representedObject];
}

- (void)togglePauseAnimatingImage:(NSMenuItem *)item {
    [self.delegate contextMenu:self toggleAnimationOfImage:item.representedObject];
}

- (void)apiMenuItem:(NSMenuItem *)item {
    NSString *identifier = item.representedObject;
    NSArray<ITMRPCRegistrationRequest *> *reqs = [iTermAPIHelper contextMenuProviderRegistrationRequests];
    for (ITMRPCRegistrationRequest *req in reqs) {
        if (![req.contextMenuAttributes.uniqueIdentifier isEqualToString:identifier]) {
            continue;
        }
        NSString *invocation = [self invocationForAPIRegistrationRequest:req];
        [iTermScriptFunctionCall callFunction:invocation
                                      timeout:req.hasTimeout ? req.timeout : 30
                                        scope:[self.delegate contextMenuSessionScope:self]
                                   retainSelf:YES
                                   completion:^(id value, NSError *error, NSSet<NSString *> *missingFunctions) {
            if (error) {
                [self.delegate contextMenu:self invocation:invocation failedWithError:error forMenuItem:item.title];
            }
        }];
        return;
    }
}

#pragma mark - API

- (NSString *)invocationForAPIRegistrationRequest:(ITMRPCRegistrationRequest *)req {
    NSArray<ITMRPCRegistrationRequest_RPCArgument *> *defaults = req.defaultsArray ?: @[];
    return [iTermAPIHelper invocationWithFullyQualifiedName:req.it_fullyQualifiedName
                                                   defaults:defaults];
}

#pragma mark - Title Bar Menu

- (NSMenu *)titleBarMenu {
    _validationClickPoint = VT100GridCoordMake(-1, -1);
    return [self menuAtCoord:VT100GridCoordMake(-1, -1)];
}

#pragma mark - NSMenuDelegate

- (void)menuDidClose:(NSMenu *)menu {
    _savedSelectedText = nil;
}

@end

