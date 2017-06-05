//
//  PseudoTerminal+TouchBar.m
//  iTerm2
//
//  Created by George Nachman on 2/20/17.
//
//

#import "PseudoTerminal+TouchBar.h"
#import "PseudoTerminal+Private.h"

#import "DebugLogging.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermColorPresets.h"
#import "iTermKeyBindingMgr.h"
#import "iTermRootTerminalView.h"
#import "iTermSystemVersion.h"
#import "iTermTouchBarButton.h"
#import "PTYTab.h"

static NSString *const iTermTabBarTouchBarIdentifier = @"tab bar";
static NSString *const iTermTabBarItemTouchBarIdentifier = @"tab bar item";

static NSString *const iTermTouchBarIdentifierAddMark = @"iTermTouchBarIdentifierAddMark";
static NSString *const iTermTouchBarIdentifierNextMark = @"iTermTouchBarIdentifierNextMark";
static NSString *const iTermTouchBarIdentifierPreviousMark = @"iTermTouchBarIdentifierPreviousMark";
static NSString *const iTermTouchBarIdentifierManPage = @"iTermTouchBarIdentifierManPage";
static NSString *const iTermTouchBarIdentifierColorPreset = @"iTermTouchBarIdentifierColorPreset";
static NSString *const iTermTouchBarIdentifierFunctionKeys = @"iTermTouchBarIdentifierFunctionKeys";
static NSString *const iTermTouchBarIdentifierColorPresetScrollview = @"iTermTouchBarIdentifierColorPresetScrollview";
static NSString *const iTermTouchBarIdentifierAutocomplete = @"iTermTouchBarIdentifierAutocomplete";
static NSString *const iTermTouchBarFunctionKeysScrollView  = @"iTermTouchBarFunctionKeysScrollView";
static NSString *const iTermTouchBarIdentifierStatus = @"iTermTouchBarIdentifierStatus";

ITERM_IGNORE_PARTIAL_BEGIN

@implementation PseudoTerminal (TouchBar) 

- (void)updateTouchBarFunctionKeyLabels {
    if (!IsTouchBarAvailable()) {
        return;
    }

    NSTouchBarItem *item = [self.touchBar itemForIdentifier:iTermTouchBarFunctionKeysScrollView];
    NSScrollView *scrollView = (NSScrollView *)item.view;
    [self updateTouchBarFunctionKeyLabelsInScrollView:scrollView];

    NSPopoverTouchBarItem *popoverItem = [self.touchBar itemForIdentifier:iTermTouchBarIdentifierFunctionKeys];
    NSTouchBar *popoverTouchBar = popoverItem.popoverTouchBar;
    item = [popoverTouchBar itemForIdentifier:iTermTouchBarFunctionKeysScrollView];
    scrollView = (NSScrollView *)item.view;
    [self updateTouchBarFunctionKeyLabelsInScrollView:scrollView];
    [self updateStatus];
}

- (void)updateTouchBarWithWordAtCursor:(NSString *)word {
    if (IsTouchBarAvailable() && [self respondsToSelector:@selector(touchBar)]) {
        NSTouchBarItem *item = [self.touchBar itemForIdentifier:iTermTouchBarIdentifierManPage];
        if (item) {
            iTermTouchBarButton *button = (iTermTouchBarButton *)item.view;
            [self updateManPageButton:button word:word];
        }
    }
}

- (void)updateStatus {
    NSTouchBarItem *item = [self.touchBar itemForIdentifier:iTermTouchBarIdentifierStatus];
    if (item) {
        iTermTouchBarButton *button = (iTermTouchBarButton *)item.view;
        NSString *touchBarStatusString = self.currentSession.keyLabels[@"status"];
        if (touchBarStatusString == nil) {
            button.title = @"Status";
            button.enabled = NO;
            item.visibilityPriority = NSTouchBarItemPriorityLow;
        } else {
            button.title = touchBarStatusString;
            button.enabled = YES;
            item.visibilityPriority = NSTouchBarItemPriorityNormal;
        }
    }
}

- (void)updateTouchBarFunctionKeyLabelsInScrollView:(NSScrollView *)scrollView {
    if (!scrollView) {
        return;
    }
    NSView *documentView = scrollView.documentView;
    NSInteger n = 1;
    for (iTermTouchBarButton *button in [documentView subviews]) {
        if (![button isKindOfClass:[iTermTouchBarButton class]]) {
            continue;
        }
        NSString *label = [NSString stringWithFormat:@"F%@", @(n)];
        NSString *customLabel = self.currentSession.keyLabels[label];
        button.title = customLabel ?: label;
        n++;
    }
}

- (NSTouchBar *)makeGenericTouchBar {
    if (!IsTouchBarAvailable()) {
        return nil;
    }
    NSTouchBar *touchBar = [[[NSTouchBar alloc] init] autorelease];
    touchBar.delegate = self;
    touchBar.defaultItemIdentifiers = @[ iTermTouchBarIdentifierManPage,
                                         iTermTouchBarIdentifierColorPreset,
                                         iTermTouchBarIdentifierFunctionKeys,
                                         NSTouchBarItemIdentifierFlexibleSpace,
                                         NSTouchBarItemIdentifierOtherItemsProxy,
                                         iTermTouchBarIdentifierAddMark,
                                         iTermTouchBarIdentifierPreviousMark,
                                         iTermTouchBarIdentifierNextMark ];
    return touchBar;
}

- (void)updateTouchBarIfNeeded {
    if (!self.wellFormed) {
        DLog(@"Not updating touch bar in %@ because not well formed", self);
        return;
    }
    if (IsTouchBarAvailable()) {
        NSTouchBar *replacement = [self amendTouchBar:[self makeGenericTouchBar]];
        if (![replacement.customizationIdentifier isEqualToString:self.touchBar.customizationIdentifier]) {
            self.touchBar = replacement;
        } else {
            NSScrubber *scrubber = (NSScrubber *)self.tabsTouchBarItem.view;
            dispatch_async(dispatch_get_main_queue(), ^{
                [scrubber reloadData];
                [scrubber setSelectedIndex:[self.tabs indexOfObject:self.currentTab]];
            });
        }
        NSArray *ids = @[ iTermTouchBarIdentifierManPage,
                          iTermTouchBarIdentifierColorPreset,
                          iTermTouchBarIdentifierFunctionKeys,
                          iTermTouchBarFunctionKeysScrollView,
                          NSTouchBarItemIdentifierFlexibleSpace,
                          iTermTouchBarIdentifierAddMark,
                          iTermTouchBarIdentifierNextMark,
                          iTermTouchBarIdentifierPreviousMark,
                          iTermTouchBarIdentifierAutocomplete,
                          iTermTouchBarIdentifierStatus ];
        ids = [ids arrayByAddingObjectsFromArray:[iTermKeyBindingMgr sortedTouchBarKeysInDictionary:[iTermKeyBindingMgr globalTouchBarMap]]];
        self.touchBar.customizationAllowedItemIdentifiers = ids;
        [self updateTouchBarFunctionKeyLabels];
    }
}

- (NSTouchBar *)amendTouchBar:(NSTouchBar *)touchBar {
    if (!IsTouchBarAvailable()) {
        return nil;
    }
    touchBar.customizationIdentifier = @"regular";
    if (self.anyFullScreen) {
        NSMutableArray *temp = [[touchBar.defaultItemIdentifiers mutableCopy] autorelease];
        NSInteger index = [temp indexOfObject:NSTouchBarItemIdentifierOtherItemsProxy];
        if (index != NSNotFound) {
            touchBar.customizationIdentifier = @"full screen";
            [temp insertObject:iTermTabBarTouchBarIdentifier atIndex:index];
            touchBar.defaultItemIdentifiers = temp;
        }
        touchBar.customizationAllowedItemIdentifiers = [touchBar.customizationAllowedItemIdentifiers arrayByAddingObjectsFromArray:@[ iTermTabBarTouchBarIdentifier ]];
    }
    return touchBar;
}

- (void)updateManPageButton:(iTermTouchBarButton *)button word:(NSString *)word {
    if (word) {
        if (![button.title isEqualToString:word]) {
            button.title = word;
            button.imagePosition = NSImageLeft;
            button.enabled = YES;
            NSString *manCommand = [NSString stringWithFormat:[iTermAdvancedSettingsModel viewManPageCommand],
                                    [word stringWithEscapedShellCharactersIncludingNewlines:YES]];
            button.keyBindingAction = @{ @"command": manCommand };
        }
    } else if (button.enabled) {
        button.title = @"";
        button.imagePosition = NSImageOnly;
        button.enabled = NO;
        button.keyBindingAction = nil;
    }
}

- (NSTouchBarItem *)functionKeysTouchBarItem {
    if (!IsTouchBarAvailable()) {
        return nil;
    }
    NSScrollView *scrollView = [[[NSScrollView alloc] init] autorelease];
    NSCustomTouchBarItem *item = [[[NSCustomTouchBarItem alloc] initWithIdentifier:iTermTouchBarFunctionKeysScrollView] autorelease];
    item.view = scrollView;
    NSView *documentView = [[NSView alloc] init];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = documentView;
    NSButton *previous = nil;
    for (NSInteger n = 1; n <= 20; n++) {
        NSString *label = [NSString stringWithFormat:@"F%@", @(n)];
        iTermTouchBarButton *button = [iTermTouchBarButton buttonWithTitle:label target:self action:@selector(functionKeyTouchBarItemSelected:)];
        button.tag = n;
        [button sizeToFit];
        [documentView addSubview:button];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [self addConstraintsToButton:button superView:documentView previous:previous];
        previous = button;
    }
    if (previous) {
        // Constrain last button's right to document view's right
        [self constrainButton:previous toRightOfSuperview:documentView];
    }
    item.customizationLabel = @"Function Keys";
    return item;
}

- (void)addConstraintsToButton:(iTermTouchBarButton *)button superView:(NSView *)documentView previous:(NSButton *)previous {
    if (previous == nil) {
        // Constrain the first item's left to the document view's left
        [documentView addConstraint:[NSLayoutConstraint constraintWithItem:button
                                                                 attribute:NSLayoutAttributeLeft
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:documentView
                                                                 attribute:NSLayoutAttributeLeft
                                                                multiplier:1
                                                                  constant:0]];
    } else {
        // Constrain non-first button's left to predecessor's right + 8pt
        [documentView addConstraint:[NSLayoutConstraint constraintWithItem:button
                                                                 attribute:NSLayoutAttributeLeft
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:previous
                                                                 attribute:NSLayoutAttributeRight
                                                                multiplier:1
                                                                  constant:8]];
    }
    // Constrain top and bottom to document view's top and bottom
    [documentView addConstraint:[NSLayoutConstraint constraintWithItem:button
                                                             attribute:NSLayoutAttributeTop
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:documentView
                                                             attribute:NSLayoutAttributeTop
                                                            multiplier:1
                                                              constant:0]];
    [documentView addConstraint:[NSLayoutConstraint constraintWithItem:button
                                                             attribute:NSLayoutAttributeBottom
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:documentView
                                                             attribute:NSLayoutAttributeBottom
                                                            multiplier:1
                                                              constant:0]];
}

- (void)constrainButton:(NSButton *)previous toRightOfSuperview:(NSView *)documentView {
    // Constrain button's right to document view's right
    [documentView addConstraint:[NSLayoutConstraint constraintWithItem:previous
                                                             attribute:NSLayoutAttributeRight
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:documentView
                                                             attribute:NSLayoutAttributeRight
                                                            multiplier:1
                                                              constant:0]];
}

- (NSTouchBarItem *)colorPresetsScrollViewTouchBarItem {
    if (!IsTouchBarAvailable()) {
        return nil;
    }
    NSScrollView *scrollView = [[[NSScrollView alloc] init] autorelease];
    NSCustomTouchBarItem *item = [[[NSCustomTouchBarItem alloc] initWithIdentifier:iTermTouchBarIdentifierColorPresetScrollview] autorelease];
    item.view = scrollView;
    NSView *documentView = [[NSView alloc] init];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = documentView;
    NSButton *previous = nil;
    for (NSDictionary *dict in @[ [iTermColorPresets builtInColorPresets] ?: @{},
                                  [iTermColorPresets customColorPresets] ?: @{} ]) {
        for (NSString *name in dict) {
            iTermTouchBarButton *button;
            NSColor *textColor = nil;
            NSColor *backgroundColor = nil;
            textColor = [ITAddressBookMgr decodeColor:[dict objectForKey:name][KEY_FOREGROUND_COLOR]];
            if (!textColor) {
                continue;
            }
            backgroundColor = [ITAddressBookMgr decodeColor:[dict objectForKey:name][KEY_BACKGROUND_COLOR]];
            NSDictionary *attributes = @{ NSForegroundColorAttributeName: textColor };
            NSAttributedString *title = [[[NSAttributedString alloc] initWithString:name
                                                                         attributes:attributes] autorelease];
            button = [iTermTouchBarButton buttonWithTitle:@""
                                                   target:self
                                                       action:@selector(colorPresetTouchBarItemSelected:)];
            [button sizeToFit];
            button.attributedTitle = title;
            button.bezelColor = backgroundColor;
            button.keyBindingAction = @{ @"presetName": name };
            [documentView addSubview:button];
            button.translatesAutoresizingMaskIntoConstraints = NO;
            [self addConstraintsToButton:button superView:documentView previous:previous];;
            previous = button;
        }
    }
    if (previous) {
        [self constrainButton:previous toRightOfSuperview:documentView];
    }
    return item;
}

#pragma mark - NSTouchBarDelegate

- (nullable NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    if ([identifier isEqualToString:iTermTabBarTouchBarIdentifier]) {
        NSScrubber *scrubber;
        if (!self.tabsTouchBarItem) {
            self.tabsTouchBarItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
            self.tabsTouchBarItem.customizationLabel = @"Full Screen Tab Bar";

            scrubber = [[NSScrubber alloc] initWithFrame:NSMakeRect(0, 0, 320, 30)];
            scrubber.delegate = self;   // So we can respond to selection.
            scrubber.dataSource = self;
            scrubber.showsAdditionalContentIndicators = YES;

            [scrubber registerClass:[NSScrubberTextItemView class] forItemIdentifier:iTermTabBarItemTouchBarIdentifier];

            // Use the flow layout.
            NSScrubberLayout *scrubberLayout = [[NSScrubberFlowLayout alloc] init];
            scrubber.scrubberLayout = scrubberLayout;

            scrubber.mode = NSScrubberModeFree;

            NSScrubberSelectionStyle *outlineStyle = [NSScrubberSelectionStyle outlineOverlayStyle];
            scrubber.selectionBackgroundStyle = outlineStyle;

            self.tabsTouchBarItem.view = scrubber;
        } else {
            scrubber = (NSScrubber *)self.tabsTouchBarItem.view;
        }
        // Reload the scrubber after a spin of the runloop bacause it gets laid out tighter after the
        // rest of the toolbar is created. If we reloadData now then it jumps the first time we change
        // tabs.
        dispatch_async(dispatch_get_main_queue(), ^{
            [scrubber reloadData];
            [scrubber setSelectedIndex:[self.tabs indexOfObject:self.currentTab]];
        });


        return self.tabsTouchBarItem;
    } else if ([identifier isEqualToString:iTermTouchBarIdentifierAutocomplete]) {
        self.autocompleteCandidateListItem = [[NSCandidateListTouchBarItem alloc] initWithIdentifier:identifier];
        self.autocompleteCandidateListItem.delegate = self;
        self.autocompleteCandidateListItem.customizationLabel = @"Autocomplete Suggestions";
        NSAttributedString *(^commandUseToAttributedString)(NSString *commandUse,
                                                            NSInteger index) = ^(NSString *command,
                                                                                 NSInteger index) {
            return [[[NSAttributedString alloc] initWithString:command ?: @""] autorelease];
        };
        self.autocompleteCandidateListItem.attributedStringForCandidate = commandUseToAttributedString;
        return self.autocompleteCandidateListItem;
    }

    NSImage *image = nil;
    SEL selector = NULL;
    NSString *label = nil;

    if ([identifier isEqualToString:iTermTouchBarIdentifierManPage]) {
        selector = @selector(manPageTouchBarItemSelected:);
        label = @"Man Page";
    } else if ([identifier isEqualToString:iTermTouchBarIdentifierStatus]) {
        selector = @selector(statusTouchBarItemSelected:);
        label = @"Your Message Here";
    } else if ([identifier isEqualToString:iTermTouchBarIdentifierAddMark]) {
        image = [[NSImage imageNamed:@"Add Mark Touch Bar Icon"] imageWithColor:[NSColor labelColor]];
        selector = @selector(addMarkTouchBarItemSelected:);
        label = @"Add Mark";
    } else if ([identifier isEqualToString:iTermTouchBarIdentifierNextMark]) {
        image = [NSImage imageNamed:NSImageNameTouchBarGoDownTemplate];
        selector = @selector(nextMarkTouchBarItemSelected:);
        label = @"Next Mark";
    } else if ([identifier isEqualToString:iTermTouchBarIdentifierPreviousMark]) {
        image = [NSImage imageNamed:NSImageNameTouchBarGoUpTemplate];
        selector = @selector(previousMarkTouchBarItemSelected:);
        label = @"Previous Mark";
    } else if ([identifier isEqualToString:iTermTouchBarIdentifierColorPreset]) {
        image = [NSImage imageNamed:NSImageNameTouchBarColorPickerFill];
        selector = @selector(colorPresetTouchBarItemSelected:);
        NSPopoverTouchBarItem *item = [[[NSPopoverTouchBarItem alloc] initWithIdentifier:identifier] autorelease];
        item.customizationLabel = @"Color Preset";
        item.showsCloseButton = YES;
        item.collapsedRepresentationImage = image;

        NSTouchBar *secondaryTouchBar = [[[NSTouchBar alloc] init] autorelease];
        secondaryTouchBar.delegate = self;
        secondaryTouchBar.defaultItemIdentifiers = @[ iTermTouchBarIdentifierColorPresetScrollview ];
        item.popoverTouchBar = secondaryTouchBar;
        return item;
    } else if ([identifier isEqualToString:iTermTouchBarIdentifierFunctionKeys]) {
        image = [NSImage imageNamed:@"Touch Bar Function Keys"];
        NSPopoverTouchBarItem *item = [[[NSPopoverTouchBarItem alloc] initWithIdentifier:identifier] autorelease];
        item.customizationLabel = @"Function Keys Popover";
        item.showsCloseButton = YES;
        item.collapsedRepresentationImage = image;

        NSTouchBar *functionKeys = [[[NSTouchBar alloc] init] autorelease];
        functionKeys.delegate = self;
        functionKeys.defaultItemIdentifiers = @[ iTermTouchBarFunctionKeysScrollView ];
        item.popoverTouchBar = functionKeys;
        return item;
    } else if ([identifier isEqualToString:iTermTouchBarFunctionKeysScrollView]) {
        return [self functionKeysTouchBarItem];
    } else if ([identifier isEqualToString:iTermTouchBarIdentifierColorPresetScrollview]) {
        return [self colorPresetsScrollViewTouchBarItem];
    }

    if (image || label) {
        iTermTouchBarButton *button;
        if (image) {
            button = [iTermTouchBarButton buttonWithImage:image target:self action:selector];
        } else {
            button = [iTermTouchBarButton buttonWithTitle:label target:self action:selector];
        }
        NSCustomTouchBarItem *item = [[[NSCustomTouchBarItem alloc] initWithIdentifier:identifier] autorelease];
        item.view = button;
        item.customizationLabel = label;
        if ([identifier isEqualToString:iTermTouchBarIdentifierManPage]) {
            button.title = @"";
            button.image = [NSImage imageNamed:@"Man Page Touch Bar Icon"];
            button.imagePosition = NSImageOnly;
            button.enabled = NO;
        }
        return item;
    }
    NSDictionary *map = [iTermKeyBindingMgr globalTouchBarMap];
    NSDictionary *binding = map[identifier];

    if (!binding) {
        return nil;
    }
    NSCustomTouchBarItem *item = [[[NSCustomTouchBarItem alloc] initWithIdentifier:identifier] autorelease];
    iTermTouchBarButton *button = [iTermTouchBarButton buttonWithTitle:[iTermKeyBindingMgr touchBarLabelForBinding:binding]
                                                                target:self
                                                                action:@selector(touchBarItemSelected:)];
    button.keyBindingAction = binding;
    item.view = button;
    item.view.identifier = identifier;
    item.customizationLabel = [iTermKeyBindingMgr formatAction:binding];

    return item;
}

- (void)touchBarItemSelected:(iTermTouchBarButton *)sender {
    NSDictionary *binding = sender.keyBindingAction;
    [self.currentSession performKeyBindingAction:[iTermKeyBindingMgr actionForTouchBarItemBinding:binding]
                                       parameter:[iTermKeyBindingMgr parameterForTouchBarItemBinding:binding]
                                           event:[NSApp currentEvent]];
}

- (void)addMarkTouchBarItemSelected:(id)sender {
    [self.currentSession screenSaveScrollPosition];
}

- (void)nextMarkTouchBarItemSelected:(id)sender {
    [self.currentSession nextMarkOrNote];
}

- (void)previousMarkTouchBarItemSelected:(id)sender {
    [self.currentSession previousMarkOrNote];
}

- (void)manPageTouchBarItemSelected:(iTermTouchBarButton *)sender {
    NSString *command = sender.keyBindingAction[@"command"];
    if (command) {
        NSString *escapedCommand = [command stringWithEscapedShellCharactersIncludingNewlines:YES];
        command = [NSString stringWithFormat:@"sh -c \"%@\"", escapedCommand];
        [[iTermController sharedInstance] launchBookmark:nil
                                              inTerminal:nil
                                                 withURL:nil
                                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                 makeKey:YES
                                             canActivate:YES
                                                 command:command
                                                   block:^PTYSession *(Profile *profile, PseudoTerminal *term) {
                                                       profile = [profile dictionaryBySettingObject:@"" forKey:KEY_INITIAL_TEXT];
                                                       return [term createTabWithProfile:profile withCommand:command];
                                                   }];
    }
}

- (void)statusTouchBarItemSelected:(iTermTouchBarButton *)sender {
    [self.currentSession jumpToLocationWhereCurrentStatusChanged];
}

- (void)colorPresetTouchBarItemSelected:(iTermTouchBarButton *)sender {
    [self.currentSession setColorsFromPresetNamed:sender.keyBindingAction[@"presetName"]];
}

- (void)functionKeyTouchBarItemSelected:(iTermTouchBarButton *)sender {
    [self sendFunctionKeyToCurrentSession:sender.tag];
}

- (void)sendFunctionKeyToCurrentSession:(NSInteger)number {
    if (number < 1 || number > 20) {
        return;
    }

    NSEvent *currentEvent = [NSApp currentEvent];
    unsigned short keyCodes[] = {
        kVK_F1,
        kVK_F2,
        kVK_F3,
        kVK_F4,
        kVK_F5,
        kVK_F6,
        kVK_F7,
        kVK_F8,
        kVK_F9,
        kVK_F10,
        kVK_F11,
        kVK_F12,
        kVK_F13,
        kVK_F14,
        kVK_F15,
        kVK_F16,
        kVK_F17,
        kVK_F18,
        kVK_F19,
        kVK_F20,
    };
    NSString *chars = [NSString stringWithFormat:@"%C", (unichar)(NSF1FunctionKey + number - 1)];
    NSPoint screenPoint = [NSEvent mouseLocation];
    NSEvent *event = [NSEvent keyEventWithType:NSKeyDown
                                      location:[self.window convertRectFromScreen:NSMakeRect(screenPoint.x, screenPoint.y, 0, 0)].origin
                                 modifierFlags:([NSEvent modifierFlags] | NSFunctionKeyMask)
                                     timestamp:[currentEvent timestamp]
                                  windowNumber:self.window.windowNumber
                                       context:nil
                                    characters:chars
                   charactersIgnoringModifiers:chars
                                     isARepeat:NO
                                       keyCode:keyCodes[number - 1]];
    [self.currentSession.textview keyDown:event];
}

- (void)candidateListTouchBarItem:(NSCandidateListTouchBarItem *)anItem endSelectingCandidateAtIndex:(NSInteger)index {
    if (index != NSNotFound) {
        NSString *command = [anItem candidates][index];
        NSString *prefix = self.currentSession.currentCommand;
        if ([command hasPrefix:prefix] || prefix.length == 0) {
            [self.currentSession insertText:[command substringFromIndex:prefix.length]];
        }
    }
}

#pragma mark - NSScrubberDelegate

- (void)scrubber:(NSScrubber *)scrubber didSelectItemAtIndex:(NSInteger)selectedIndex {
    [self.tabView selectTabViewItemAtIndex:selectedIndex];
}

#pragma mark - NSScrubberDataSource

- (NSInteger)numberOfItemsForScrubber:(NSScrubber *)scrubber {
    return [self.contentView.tabView numberOfTabViewItems];
}

- (NSString *)scrubber:(NSScrubber *)scrubber labelAtIndex:(NSInteger)index {
    NSArray<PTYTab *> *tabs = self.tabs;
    return index < tabs.count ?  self.tabs[index].activeSession.name : @"";
}

- (__kindof NSScrubberItemView *)scrubber:(NSScrubber *)scrubber viewForItemAtIndex:(NSInteger)index {
    NSScrubberTextItemView *itemView = [scrubber makeItemWithIdentifier:iTermTabBarItemTouchBarIdentifier owner:nil];
    itemView.textField.stringValue = [self scrubber:scrubber labelAtIndex:index] ?: @"";
    return itemView;
}

- (NSSize)scrubber:(NSScrubber *)scrubber layout:(NSScrubberFlowLayout *)layout sizeForItemAtIndex:(NSInteger)itemIndex {
    NSSize size = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);

    NSString *title = [self scrubber:scrubber labelAtIndex:itemIndex];
    NSRect textRect = [title boundingRectWithSize:size
                                          options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                       attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:0]}];
    // Apple says: "+10: NSTextField horizontal padding, no good way to retrieve this though. +6 for spacing."
    // 8 is because the items become smaller the first time you change tabs for some mysterious reason
    // and that leaves enough room for them. :(
    // The 30 is also Apple's magic number.
    return NSMakeSize(textRect.size.width + 10 + 6 + 8, 30);
}

@end

ITERM_IGNORE_PARTIAL_END

