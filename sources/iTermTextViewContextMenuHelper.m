//
//  iTermTextViewContextMenuHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/30/20.
//

#import "iTermTextViewContextMenuHelper.h"

#import "DebugLogging.h"
#import "NSURL+iTerm.h"
#import "SCPPath.h"
#import "SmartSelectionController.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"
#import "iTermAPIHelper.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermImageInfo.h"
#import "iTermPreferences.h"
#import "iTermScriptFunctionCall.h"
#import "iTermSelection.h"
#import "iTermTextExtractor.h"
#import "iTermURLActionHelper.h"
#import "iTermVariableScope.h"
#import "NSColor+iTerm.h"
#import "RegexKitLite.h"
#import "WindowControllerInterface.h"

static const int kMaxSelectedTextLengthForCustomActions = 400;

@interface NSString(ContextMenu)
- (NSArray<NSString *> *)helpfulSynonyms;
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
              @(kRunCommandInWindowContextMenuAction): NSStringFromSelector(@selector(contextMenuActionRunCommandInWindow:)) };
}

// This method is called by control-click or by clicking the hamburger icon in the session title bar.
// Two-finger tap (or presumably right click with a mouse) would go through mouseUp->
// PointerController->openContextMenuWithEvent.
- (NSMenu *)menuForEvent:(NSEvent *)theEvent {
    if (theEvent) {
        // Control-click
        if ([iTermPreferences boolForKey:kPreferenceKeyControlLeftClickBypassesContextMenu]) {
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

- (NSMenu *)contextMenuWithEvent:(NSEvent *)event {
    const NSPoint clickPoint = [self.delegate contextMenu:self
                                               clickPoint:event
                                 allowRightMarginOverflow:NO];
    const int x = clickPoint.x;
    const int y = clickPoint.y;
    NSMenu *markMenu = nil;
    VT100ScreenMark *mark = [self.delegate contextMenu:self markOnLine:y];
    DLog(@"contextMenuWithEvent:%@ x=%d, mark=%@, mark command=%@", event, x, mark, [mark command]);
    if (mark && mark.command.length) {
        NSString *workingDirectory= [self.delegate contextMenu:self
                                        workingDirectoryOnLine:y];
        markMenu = [self menuForMark:mark directory:workingDirectory];
        NSPoint locationInWindow = [event locationInWindow];
        if (locationInWindow.x < [iTermPreferences intForKey:kPreferenceKeySideMargins]) {
            return markMenu;
        }
    }

    const VT100GridCoord coord = VT100GridCoordMake(x, y);
    iTermImageInfo *imageInfo = [self.delegate contextMenu:self imageInfoAtCoord:coord];

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
    if (markMenu) {
        NSMenuItem *markItem = [[NSMenuItem alloc] initWithTitle:@"Command Info"
                                                          action:nil
                                                   keyEquivalent:@""];
        markItem.submenu = markMenu;
        [contextMenu insertItem:markItem atIndex:0];
        [contextMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
    }

    return contextMenu;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if ([item action] == @selector(downloadWithSCP:)) {
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
        [item action] == @selector(copyString:)) {
        return YES;
    }
    if ([item action] == @selector(stopCoprocess:)) {
        return [self.delegate contextMenuHasCoprocess:self];
    }
    if ([item action] == @selector(bury:)) {
        return [self.delegate contextMenuCanBurySession:self];
    }
    if ([item action] == @selector(selectCommandOutput:)) {
        VT100ScreenMark *commandMark = [item representedObject];
        return [self.delegate contextMenu:self hasOutputForCommandMark:commandMark];
    }
    if ([item action] == @selector(sendSelection:) ||
        [item action] == @selector(addNote:) ||
        [item action] == @selector(mail:) ||
        [item action] == @selector(browse:) ||
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

    if ([self.smartSelectionActionSelectorDictionary.allValues containsObject:NSStringFromSelector(item.action)]) {
        return YES;
    }

    return NO;
}

#pragma mark - Private

static int32_t iTermInt32FromBytes(const unsigned char *bytes, BOOL bigEndian) {
    uint32_t i;
    if (bigEndian) {
        i = ((((uint32_t)bytes[0]) << 24) |
             (((uint32_t)bytes[1]) << 16) |
             (((uint32_t)bytes[2]) << 8) |
             (((uint32_t)bytes[3]) << 0));
    } else {
        i = ((((uint32_t)bytes[3]) << 24) |
             (((uint32_t)bytes[2]) << 16) |
             (((uint32_t)bytes[1]) << 8) |
             (((uint32_t)bytes[0]) << 0));
    }
    return i;
}

static uint64_t iTermInt64FromBytes(const unsigned char *bytes, BOOL bigEndian) {
    uint64_t i;
    if (bigEndian) {
        i = ((((uint64_t)bytes[0]) << 56) |
             (((uint64_t)bytes[1]) << 48) |
             (((uint64_t)bytes[2]) << 40) |
             (((uint64_t)bytes[3]) << 32) |
             (((uint64_t)bytes[4]) << 24) |
             (((uint64_t)bytes[5]) << 16) |
             (((uint64_t)bytes[6]) << 8) |
             (((uint64_t)bytes[7]) << 0));
    } else {
        i = ((((uint64_t)bytes[7]) << 56) |
             (((uint64_t)bytes[6]) << 48) |
             (((uint64_t)bytes[5]) << 40) |
             (((uint64_t)bytes[4]) << 32) |
             (((uint64_t)bytes[3]) << 24) |
             (((uint64_t)bytes[2]) << 16) |
             (((uint64_t)bytes[1]) << 8) |
             (((uint64_t)bytes[0]) << 0));
    }
    return i;
}


- (NSMenu *)menuAtCoord:(VT100GridCoord)coord {
    NSMenu *theMenu;

    // Allocate a menu
    theMenu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];
    iTermImageInfo *imageInfo = [self.delegate contextMenu:self imageInfoAtCoord:coord];
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
            NSArray<NSString *> *synonyms = [shortSelectedText helpfulSynonyms];
            needSeparator = synonyms.count > 0;
            for (NSString *conversion in synonyms) {
                NSMenuItem *theItem = [[NSMenuItem alloc] init];
                theItem.title = conversion;
                [theMenu addItem:theItem];
            }
            NSArray *captures = [shortSelectedText captureComponentsMatchedByRegex:@"^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$"];
            if (captures.count) {
                NSMenuItem *theItem = [[NSMenuItem alloc] init];
                NSColor *color = [NSColor colorFromHexString:shortSelectedText];
                if (color) {
                    CGFloat x;
                    if (@available(macOS 10.16, *)) {
                        x = 15;
                    } else {
                        x = 11;
                    }
                    const CGFloat margin = 2;
                    const CGFloat height = 24;
                    const CGFloat width = 24;
                    NSView *wrapper = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width + x, height + margin * 2)];
                    NSView *colorView = [[NSView alloc] initWithFrame:NSMakeRect(x, margin, width, height)];
                    colorView.wantsLayer = YES;
                    colorView.layer = [[CALayer alloc] init];
                    colorView.layer.backgroundColor = [color CGColor];
                    colorView.layer.borderColor = [color.isDark ? [NSColor colorWithWhite:0.8 alpha:1] : [NSColor colorWithWhite:0.2 alpha:1] CGColor];
                    colorView.layer.borderWidth = 1;
                    colorView.layer.cornerRadius = 3;
                    wrapper.autoresizesSubviews = YES;
                    colorView.autoresizingMask = NSViewMaxXMargin;
                    [wrapper addSubview:colorView];
                    theItem.view = wrapper;
                    [theMenu addItem:theItem];
                    needSeparator = YES;
                }
            }
        }
        if ([self.delegate contextMenuSelectionIsReasonable:self]) {
            NSString *text = [self.delegate contextMenuSelectedText:self capped:0];
            NSData *data = [text dataFromWhitespaceDelimitedHexValues];
            if (data.length > 0) {
                NSMenuItem *theItem = nil;
                if (data.length > 1) {
                    if (data.length == 4) {
                        const uint32_t be = iTermInt32FromBytes(data.bytes, YES);
                        theItem = [[NSMenuItem alloc] init];
                        theItem.title = [NSString stringWithFormat:@"Big-Endian int32: %@", @(be)];
                        theItem.target = self;
                        theItem.action = @selector(copyString:);
                        theItem.representedObject = [@(be) stringValue];
                        [theMenu addItem:theItem];

                        const uint32_t le = iTermInt32FromBytes(data.bytes, NO);
                        theItem = [[NSMenuItem alloc] init];
                        theItem.title = [NSString stringWithFormat:@"Little-Endian int32: %@", @(le)];
                        theItem.target = self;
                        theItem.action = @selector(copyString:);
                        theItem.representedObject = [@(le) stringValue];
                        [theMenu addItem:theItem];

                        needSeparator = YES;
                    } else if (data.length == 8) {
                        const uint64_t be = iTermInt64FromBytes(data.bytes, YES);
                        theItem = [[NSMenuItem alloc] init];
                        theItem.title = [NSString stringWithFormat:@"Big-Endian int64: %@", @(be)];
                        theItem.target = self;
                        theItem.action = @selector(copyString:);
                        theItem.representedObject = [@(be) stringValue];
                        [theMenu addItem:theItem];

                        const uint64_t le = iTermInt64FromBytes(data.bytes, NO);
                        theItem = [[NSMenuItem alloc] init];
                        theItem.title = [NSString stringWithFormat:@"Little-Endian int64: %@", @(le)];
                        theItem.target = self;
                        theItem.action = @selector(copyString:);
                        theItem.representedObject = [@(le) stringValue];
                        [theMenu addItem:theItem];

                        needSeparator = YES;
                    } else if (data.length < 100) {
                        NSString *stringValue = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                        if (stringValue) {
                            theItem = [[NSMenuItem alloc] init];
                            theItem.title = [NSString stringWithFormat:@"%@ UTF-8 bytes: %@", @(data.length), stringValue];
                            theItem.target = self;
                            theItem.action = @selector(copyString:);
                            theItem.representedObject = stringValue;
                            [theMenu addItem:theItem];
                            needSeparator = YES;
                        }
                    }
                    if (!theItem && data.length > 4) {
                        theItem = [[NSMenuItem alloc] init];
                        theItem.title = [NSString stringWithFormat:@"%@ hex bytes", @(data.length)];
                        [theMenu addItem:theItem];
                        needSeparator = YES;
                    }
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
    [theMenu addItem:terminalState];

    [self.delegate contextMenu:self addContextMenuItems:theMenu];

    return theMenu;
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
                    VT100RemoteHost *remoteHost = [self.delegate contextMenu:self remoteHostOnLine:line];
                    NSString *theTitle =
                        [ContextMenuActionPrefsController titleForActionDict:action
                                                       withCaptureComponents:components
                                                            workingDirectory:workingDirectory
                                                                  remoteHost:remoteHost];

                    NSMenuItem *theItem = [[NSMenuItem alloc] initWithTitle:theTitle
                                                                     action:mySelector
                                                              keyEquivalent:@""];
                    [theItem setRepresentedObject:@{ iTermSmartSelectionActionContextKeyAction: action,
                                                     iTermSmartSelectionActionContextKeyComponents: components,
                                                     iTermSmartSelectionActionContextKeyWorkingDirectory: workingDirectory,
                                                     iTermSmartSelectionActionContextKeyRemoteHost: remoteHost} ];
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

- (NSMenu *)menuForMark:(VT100ScreenMark *)mark directory:(NSString *)directory {
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

- (void)contextMenuActionOpenFile:(id)sender {
    DLog(@"Open file: '%@'", [sender representedObject]);
    NSDictionary *dict = [sender representedObject];
    [self evaluateCustomActionDictionary:dict completion:^(NSString *value) {
        if (!value) {
            return;
        }
        [[NSWorkspace sharedWorkspace] openFile:[value stringByExpandingTildeInPath]];
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
    NSString *command = [sender representedObject];
    DLog(@"Run command in window: %@", command);
    [self.delegate contextMenu:self runCommandInWindow:command];
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
    VT100RemoteHost *remoteHost = [dict[iTermSmartSelectionActionContextKeyRemoteHost] nilIfNull];

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
    VT100ScreenMark *mark = [sender representedObject];
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

@implementation NSString(ContextMenu)

- (NSArray<NSString *> *)helpfulSynonyms {
    NSMutableArray *array = [NSMutableArray array];
    NSString *hexOrDecimalConversion = [self hexOrDecimalConversionHelp];
    if (hexOrDecimalConversion) {
        [array addObject:hexOrDecimalConversion];
    }
    NSString *timestampConversion = [self timestampConversionHelp];
    if (timestampConversion) {
        [array addObject:timestampConversion];
    }
    NSString *utf8Help = [self utf8Help];
    if (utf8Help) {
        [array addObject:utf8Help];
    }
    if (array.count) {
        return array;
    } else {
        return nil;
    }
}

- (NSString *)hexOrDecimalConversionHelp {
    unsigned long long value;
    BOOL mustBePositive = NO;
    BOOL decToHex;
    BOOL is32bit;
    if ([self hasPrefix:@"0x"] && [self length] <= 18) {
        decToHex = NO;
        NSScanner *scanner = [NSScanner scannerWithString:self];
        [scanner setScanLocation:2]; // bypass 0x
        if (![scanner scanHexLongLong:&value]) {
            return nil;
        }
        is32bit = [self length] <= 10;
    } else {
        if (![[self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] isNumeric]) {
            return nil;
        }
        decToHex = YES;
        NSDecimalNumber *temp = [NSDecimalNumber decimalNumberWithString:self];
        if ([temp isEqual:[NSDecimalNumber notANumber]]) {
            return nil;
        }
        NSDecimalNumber *smallestSignedLongLong =
            [NSDecimalNumber decimalNumberWithString:@"-9223372036854775808"];
        NSDecimalNumber *largestUnsignedLongLong =
            [NSDecimalNumber decimalNumberWithString:@"18446744073709551615"];
        if ([temp doubleValue] > 0) {
            if ([temp compare:largestUnsignedLongLong] == NSOrderedDescending) {
                return nil;
            }
            mustBePositive = YES;
            is32bit = ([temp compare:@2147483648LL] == NSOrderedAscending);
        } else if ([temp compare:smallestSignedLongLong] == NSOrderedAscending) {
            // Negative but smaller than a signed 64 bit can hold
            return nil;
        } else {
            // Negative but fits in signed 64 bit
            is32bit = ([temp compare:@-2147483649LL] == NSOrderedDescending);
        }
        value = [temp unsignedLongLongValue];
    }

    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;

    NSString *humanReadableSize = [NSString stringWithHumanReadableSize:value];
    if (humanReadableSize) {
        humanReadableSize = [NSString stringWithFormat:@" (%@)", humanReadableSize];
    } else {
        humanReadableSize = @"";
    }

    if (is32bit) {
        // Value fits in a signed 32-bit value, so treat it as such
        int intValue =
        (int)value;
        NSString *formattedDecimalValue = [numberFormatter stringFromNumber:@(intValue)];
        if (decToHex) {
            if (intValue < 0) {
                humanReadableSize = @"";
            }
            return [NSString stringWithFormat:@"%@ = 0x%x%@",
                       formattedDecimalValue, intValue, humanReadableSize];
        } else if (intValue >= 0) {
            return [NSString stringWithFormat:@"0x%x = %@%@",
                       intValue, formattedDecimalValue, humanReadableSize];
        } else {
            unsigned int unsignedIntValue = (unsigned int)value;
            NSString *formattedUnsignedDecimalValue =
                [numberFormatter stringFromNumber:@(unsignedIntValue)];
            return [NSString stringWithFormat:@"0x%x = %@ or %@%@",
                       intValue, formattedDecimalValue, formattedUnsignedDecimalValue,
                       humanReadableSize];
        }
    } else {
        // 64-bit value
        NSDecimalNumber *decimalNumber;
        long long signedValue = value;
        if (!mustBePositive && signedValue < 0) {
            decimalNumber = [NSDecimalNumber decimalNumberWithMantissa:-signedValue
                                                              exponent:0
                                                            isNegative:YES];
        } else {
            decimalNumber = [NSDecimalNumber decimalNumberWithMantissa:value
                                                              exponent:0
                                                            isNegative:NO];
        }
        NSString *formattedDecimalValue = [numberFormatter stringFromNumber:decimalNumber];
        if (decToHex) {
            if (!mustBePositive && signedValue < 0) {
                humanReadableSize = @"";
            }
            return [NSString stringWithFormat:@"%@ = 0x%llx%@",
                       formattedDecimalValue, value, humanReadableSize];
        } else if (signedValue >= 0) {
            return [NSString stringWithFormat:@"0x%llx = %@%@",
                       value, formattedDecimalValue, humanReadableSize];
        } else {
            // Value is negative and converting hex to decimal.
            NSDecimalNumber *unsignedDecimalNumber =
                [NSDecimalNumber decimalNumberWithMantissa:value
                                                  exponent:0
                                                isNegative:NO];
            NSString *formattedUnsignedDecimalValue =
                [numberFormatter stringFromNumber:unsignedDecimalNumber];
            return [NSString stringWithFormat:@"0x%llx = %@ or %@%@",
                       value, formattedDecimalValue, formattedUnsignedDecimalValue,
                       humanReadableSize];
        }
    }
}

- (NSString *)timestampConversionHelp {
    NSDate *date;
    date = [self dateValueFromUnix];
    if (!date) {
        date = [self dateValueFromUTC];
    }
    if (date) {
        NSString *template;
        if (fmod(date.timeIntervalSince1970, 1) > 0.001) {
            template = @"yyyyMMMd hh:mm:ss.SSS z";
        } else {
            template = @"yyyyMMMd hh:mm:ss z";
        }
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:template
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
        return [fmt stringFromDate:date];
    } else {
        return nil;
    }
}

+ (instancetype)stringWithHumanReadableSize:(unsigned long long)value {
    if (value < 1024) {
        return nil;
    }
    unsigned long long num = value;
    int pow = 0;
    BOOL exact = YES;
    while (num >= 1024 * 1024) {
        pow++;
        if (num % 1024 != 0) {
            exact = NO;
        }
        num /= 1024;
    }
    // Show 2 fraction digits, always rounding downwards. Printf rounds floats to the nearest
    // representable value, so do the calculation with integers until we get 100-fold the desired
    // value, and then switch to float.
    if (100 * num % 1024 != 0) {
        exact = NO;
    }
    num = 100 * num / 1024;
    NSArray *iecPrefixes = @[ @"Ki", @"Mi", @"Gi", @"Ti", @"Pi", @"Ei" ];
    return [NSString stringWithFormat:@"%@%.2f %@",
               exact ? @"" :@ "≈", (double)num / 100, iecPrefixes[pow]];
}

- (NSString *)utf8Help {
    if (self.length == 0) {
        return nil;
    }

    CFRange graphemeClusterRange = CFStringGetRangeOfComposedCharactersAtIndex((CFStringRef)self, 0);
    if (graphemeClusterRange.location != 0 ||
        graphemeClusterRange.length != self.length) {
        // Only works for a single grapheme cluster.
        return nil;
    }

    if ([self characterAtIndex:0] < 128 && self.length == 1) {
        // No help for ASCII
        return nil;
    }

    // Convert to UCS-4
    NSData *data = [self dataUsingEncoding:NSUTF32StringEncoding];
    const int *characters = (int *)data.bytes;
    int numCharacters = data.length / 4;

    // Output UTF-8 hex codes
    NSMutableArray *byteStrings = [NSMutableArray array];
    const char *utf8 = [self UTF8String];
    for (size_t i = 0; utf8[i]; i++) {
        [byteStrings addObject:[NSString stringWithFormat:@"0x%02x", utf8[i] & 0xff]];
    }
    NSString *utf8String = [byteStrings componentsJoinedByString:@" "];

    // Output UCS-4 hex codes
    NSMutableArray *ucs4Strings = [NSMutableArray array];
    for (NSUInteger i = 0; i < numCharacters; i++) {
        if (characters[i] == 0xfeff) {
            // Ignore byte order mark
            continue;
        }
        [ucs4Strings addObject:[NSString stringWithFormat:@"U+%04x", characters[i]]];
    }
    NSString *ucs4String = [ucs4Strings componentsJoinedByString:@" "];

    return [NSString stringWithFormat:@"“%@” = %@ = %@ (UTF-8)", self, ucs4String, utf8String];
}

- (NSDate *)dateValueFromUnix {
    typedef struct {
        NSString *regex;
        double divisor;
    } Format;
    // TODO: Change these regexes to begin with ^[12] in the year 2032 or so.
    Format formats[] = {
        {
            .regex = @"^1[0-9]{9}$",
            .divisor = 1
        },
        {
            .regex = @"^1[0-9]{12}$",
            .divisor = 1000
        },
        {
            .regex = @"^1[0-9]{15}$",
            .divisor = 1000000
        },
        {
            .regex = @"^1[0-9]{9}\\.[0-9]+$",
            .divisor = 1
        }
    };
    for (size_t i = 0; i < sizeof(formats) / sizeof(*formats); i++) {
        if ([self isMatchedByRegex:formats[i].regex]) {
            const NSTimeInterval timestamp = [self doubleValue] / formats[i].divisor;
            return [NSDate dateWithTimeIntervalSince1970:timestamp];
        }
    }
    return nil;
}

- (NSDate *)dateValueFromUTC {
    NSArray<NSString *> *formats = @[ @"E, d MMM yyyy HH:mm:ss zzz",
                                      @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                                      @"yyyy-MM-dd't'HH:mm:ss.SSS'z'",
                                      @"yyyy-MM-dd'T'HH:mm:ss'Z'",
                                      @"yyyy-MM-dd't'HH:mm:ss'z'",
                                      @"yyyy-MM-dd'T'HH:mm'Z'",
                                      @"yyyy-MM-dd't'HH:mm'z'" ];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    for (NSString *format in formats) {
        dateFormatter.dateFormat = format;
        dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        NSDate *date = [dateFormatter dateFromString:self];
        if (date) {
            return date;
        }
    }
    return nil;
}

@end

