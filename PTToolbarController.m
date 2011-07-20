/*
 **  PTToolbarController.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: manages an the toolbar.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "PTToolbarController.h"
#import "iTermController.h"
#import "PseudoTerminal.h"
#import "ITAddressBookMgr.h"
#import "BookmarksWindow.h"

NSString *NewToolbarItem = @"New";
NSString *BookmarksToolbarItem = @"Profiles";
NSString *CloseToolbarItem = @"Close";
NSString *ConfigToolbarItem = @"Info";
NSString *CommandToolbarItem = @"Command";

@interface PTToolbarController (Private)
- (void)setupToolbar;
- (void)buildToolbarItemPopUpMenu:(NSToolbarItem *)toolbarItem forToolbar:(NSToolbar *)toolbar;
- (NSToolbarItem*)toolbarItemWithIdentifier:(NSString*)identifier;
@end

@implementation PTToolbarController

- (id)initWithPseudoTerminal:(PseudoTerminal*)terminal;
{
    self = [super init];
    _pseudoTerminal = terminal; // don't retain;

    // Add ourselves as an observer for notifications to reload the addressbook.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(reloadAddressBookMenu:)
                                                 name: @"iTermReloadAddressBook"
                                               object: nil];

    [self setupToolbar];
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [iconMenu_ release];
    [textMenu_ release];
    [_toolbar release];
    [super dealloc];
}

- (NSArray *)toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar
{
    NSMutableArray* itemIdentifiers= [[[NSMutableArray alloc]init] autorelease];

    [itemIdentifiers addObject: NewToolbarItem];
    [itemIdentifiers addObject: ConfigToolbarItem];
    [itemIdentifiers addObject: NSToolbarSeparatorItemIdentifier];
    [itemIdentifiers addObject: NSToolbarCustomizeToolbarItemIdentifier];
    [itemIdentifiers addObject: CloseToolbarItem];
    [itemIdentifiers addObject: NSToolbarSeparatorItemIdentifier];
    [itemIdentifiers addObject: CommandToolbarItem];
    [itemIdentifiers addObject: BookmarksToolbarItem];

    return itemIdentifiers;
}

- (NSArray *)toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar
{
    NSMutableArray* itemIdentifiers = [[[NSMutableArray alloc]init] autorelease];

    [itemIdentifiers addObject: NewToolbarItem];
    [itemIdentifiers addObject: BookmarksToolbarItem];
    [itemIdentifiers addObject: ConfigToolbarItem];
    [itemIdentifiers addObject: NSToolbarCustomizeToolbarItemIdentifier];
    [itemIdentifiers addObject: CloseToolbarItem];
    [itemIdentifiers addObject: CommandToolbarItem];
    [itemIdentifiers addObject: NSToolbarFlexibleSpaceItemIdentifier];
    [itemIdentifiers addObject: NSToolbarSpaceItemIdentifier];
    [itemIdentifiers addObject: NSToolbarSeparatorItemIdentifier];

    return itemIdentifiers;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier: (NSString *)itemIdent
    willBeInsertedIntoToolbar:(BOOL)willBeInserted
{
    NSToolbarItem *toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdent] autorelease];
    NSBundle *thisBundle = [NSBundle bundleForClass:[self class]];
    NSString *imagePath;
    NSImage *anImage;

    if ([itemIdent isEqual:CloseToolbarItem]) {
        [toolbarItem setLabel:NSLocalizedStringFromTableInBundle(@"Close",@"iTerm", thisBundle, @"Toolbar Item: Close Session")];
        [toolbarItem setPaletteLabel:NSLocalizedStringFromTableInBundle(@"Close",@"iTerm", thisBundle, @"Toolbar Item: Close Session")];
        [toolbarItem setToolTip:NSLocalizedStringFromTableInBundle(@"Close the current session",@"iTerm", thisBundle, @"Toolbar Item Tip: Close")];
        imagePath = [thisBundle pathForResource:@"close"
                                         ofType:@"png"];
        anImage = [[NSImage alloc] initByReferencingFile:imagePath];
        [toolbarItem setImage:anImage];
        [anImage release];
        [toolbarItem setTarget:nil];
        [toolbarItem setAction:@selector(closeCurrentSession:)];
    } else if ([itemIdent isEqual:ConfigToolbarItem]) {
        [toolbarItem setLabel:NSLocalizedStringFromTableInBundle(@"Info",@"iTerm", thisBundle, @"Toolbar Item:Info") ];
        [toolbarItem setPaletteLabel:NSLocalizedStringFromTableInBundle(@"Info",@"iTerm", thisBundle, @"Toolbar Item:Info") ];
        [toolbarItem setToolTip:NSLocalizedStringFromTableInBundle(@"Window/Session Info",@"iTerm", thisBundle, @"Toolbar Item Tip:Info")];
        imagePath = [thisBundle pathForResource:@"config"
                                         ofType:@"png"];
        anImage = [[NSImage alloc] initByReferencingFile:imagePath];
        [toolbarItem setImage:anImage];
        [anImage release];
        [toolbarItem setTarget:nil];
        [toolbarItem setAction:@selector(editCurrentSession:)];
    } else if ([itemIdent isEqual:BookmarksToolbarItem]) {
        [toolbarItem setLabel:NSLocalizedStringFromTableInBundle(@"Profiles",@"iTerm", thisBundle, @"Toolbar Item: Profiles") ];
        [toolbarItem setPaletteLabel:NSLocalizedStringFromTableInBundle(@"Profiles",@"iTerm", thisBundle, @"Toolbar Item: Profiles") ];
        [toolbarItem setToolTip:NSLocalizedStringFromTableInBundle(@"Profiles",@"iTerm", thisBundle, @"Toolbar Item Tip: Profiles")];
        imagePath = nil;
        anImage = [[NSImage imageNamed:NSImageNameUserAccounts] copy];
        [toolbarItem setImage:anImage];
        [anImage release];
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(toggleBookmarksView:)];
    }  else if ([itemIdent isEqual:NewToolbarItem]) {
        NSPopUpButton *aPopUpButton;

        if([toolbar sizeMode] == NSToolbarSizeModeSmall)
            aPopUpButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 42, 30.0) pullsDown:YES];
        else
            aPopUpButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 48, 32.0) pullsDown:YES];

        [aPopUpButton setTarget:nil];
        [aPopUpButton setBordered:NO];
        [[aPopUpButton cell] setArrowPosition:NSPopUpNoArrow];
        [toolbarItem setView:aPopUpButton];
        // Release the popup button since it is retained by the toolbar item.
        [aPopUpButton release];

        // build the menu
        [self buildToolbarItemPopUpMenu:toolbarItem forToolbar:toolbar];

        NSSize sz = [aPopUpButton bounds].size;
        //sz.width += 8;
        [toolbarItem setMinSize:sz];
        [toolbarItem setMaxSize:sz];
        [toolbarItem setLabel:NSLocalizedStringFromTableInBundle(@"New",@"iTerm", thisBundle, @"Toolbar Item:New")];
        [toolbarItem setPaletteLabel:NSLocalizedStringFromTableInBundle(@"New",@"iTerm", thisBundle, @"Toolbar Item:New")];
        [toolbarItem setToolTip:NSLocalizedStringFromTableInBundle(@"Open a new session",@"iTerm", thisBundle, @"Toolbar Item:New")];
    } else if ([itemIdent isEqual:CommandToolbarItem]) {
        // Set up the standard properties
        [toolbarItem setLabel:NSLocalizedStringFromTableInBundle(@"Execute",@"iTerm", thisBundle, @"Toolbar Item:New")];
        [toolbarItem setPaletteLabel:NSLocalizedStringFromTableInBundle(@"Execute",@"iTerm", thisBundle, @"Toolbar Item:New")];
        [toolbarItem setToolTip:NSLocalizedStringFromTableInBundle(@"Execute Command or Launch URL",@"iTerm", thisBundle, @"Toolbar Item:New")];

        // Use a custom view, a rounded text field,
        [toolbarItem setView:[_pseudoTerminal commandField]];
        [toolbarItem setMinSize:NSMakeSize(100,NSHeight([[_pseudoTerminal commandField] frame]))];
        [toolbarItem setMaxSize:NSMakeSize(700,NSHeight([[_pseudoTerminal commandField] frame]))];

    } else {
        toolbarItem = nil;
    }

    return toolbarItem;
}

- (IBAction)toggleBookmarksView:(id)sender
{
    [[BookmarksWindow sharedInstance] showWindow:self];
}

@end

@implementation PTToolbarController (Private)

- (void)setupToolbar;
{
    _toolbar = [[NSToolbar alloc] initWithIdentifier:@"Terminal Toolbar"];
    [_toolbar setVisible:false];
    [_toolbar setDelegate:self];
    [_toolbar setAllowsUserCustomization:YES];
    [_toolbar setAutosavesConfiguration:YES];

#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
    [_toolbar setShowsBaselineSeparator:NO];
#endif

    [_toolbar setDisplayMode:NSToolbarDisplayModeDefault];
    [_toolbar insertItemWithItemIdentifier: NewToolbarItem atIndex:0];
    [_toolbar insertItemWithItemIdentifier: ConfigToolbarItem atIndex:1];
    [_toolbar insertItemWithItemIdentifier: NSToolbarFlexibleSpaceItemIdentifier atIndex:2];
    [_toolbar insertItemWithItemIdentifier: NSToolbarCustomizeToolbarItemIdentifier atIndex:3];
    [_toolbar insertItemWithItemIdentifier: NSToolbarSeparatorItemIdentifier atIndex:4];
    [_toolbar insertItemWithItemIdentifier: CommandToolbarItem atIndex:5];
    [_toolbar insertItemWithItemIdentifier: CloseToolbarItem atIndex:6];

    [[_pseudoTerminal window] setToolbar:_toolbar];

}

- (void)_removeItemsFromMenu:(NSMenu*)menu
{
    while ([menu numberOfItems] > 0) {
        NSMenuItem* item = [menu itemAtIndex:0];
        NSMenu* sub = [item submenu];
        if (sub) {
            [self _removeItemsFromMenu:sub];
        }
        [menu removeItemAtIndex:0];
    }
}

- (void)buildToolbarItemPopUpMenu:(NSToolbarItem *)toolbarItem forToolbar:(NSToolbar *)toolbar
{
    NSPopUpButton *aPopUpButton;
    NSMenuItem *item;
    NSMenu *aMenu;
    NSString *imagePath;
    NSImage *anImage;
    NSBundle *thisBundle = [NSBundle bundleForClass: [self class]];

    if (toolbarItem == nil) {
        return;
    }

    aPopUpButton = (NSPopUpButton *)[toolbarItem view];
    [aPopUpButton setAction: nil];
    // Remove menu items because otherwise they will leak (I think items and menus have a cyclic reference?)
    // As soon as -[toolbarItem setImage:] is called, the menuFormRepresentation is lost and leaked.
    [self _removeItemsFromMenu:[aPopUpButton menu]];
    // For some reason, making a call to [toolbarItem menuFormRepresentation] here causes the "new tab"
    // toolbar item to turn into the icon version so that when it's clicked in text mode the toolbar
    // switches into text+icon mode. See bug 995.
    [aPopUpButton addItemWithTitle: @""];

    [iconMenu_ release];
    iconMenu_ = aMenu = [[NSMenu alloc] init];
    // first menu item is just a space taker
    [aMenu addItem:[[[NSMenuItem alloc] initWithTitle: @"AAA" action:@selector(newSessionInTabAtIndex:) keyEquivalent:@""] autorelease]];
    [[iTermController sharedInstance] addBookmarksToMenu:aMenu startingAt:1];

    [aPopUpButton setMenu:aMenu];

    // Now set the icon
    item = [[aPopUpButton cell] menuItem];
    imagePath = [thisBundle pathForResource:@"newwin"
                                     ofType:@"png"];
    anImage = [[NSImage alloc] initByReferencingFile: imagePath];
    [anImage setScalesWhenResized:YES];
    if([toolbar sizeMode] == NSToolbarSizeModeSmall)
        [anImage setSize:NSMakeSize(24.0, 24.0)];
    else
        [anImage setSize:NSMakeSize(30.0, 30.0)];
    [toolbarItem setImage: anImage];
    [anImage release];

    [item setImage:anImage];
    [item setOnStateImage:nil];
    [item setMixedStateImage:nil];
    [aPopUpButton setPreferredEdge:NSMinXEdge];
    // Used to set horizontal edge padding to 0 in 32-bit version.

    // build a menu representation for text only.
    item = [[NSMenuItem alloc] initWithTitle: NSLocalizedStringFromTableInBundle(@"New Tab",@"iTerm", [NSBundle bundleForClass: [self class]], @"Toolbar Item:New") action: nil keyEquivalent: @""];
    [textMenu_ release];
    textMenu_ = aMenu = [[NSMenu alloc] init];
    [[iTermController sharedInstance] addBookmarksToMenu:aMenu startingAt:0];
    [item setSubmenu:aMenu];

    [toolbarItem setMenuFormRepresentation: item];
    [item release];
}

// Reloads the addressbook entries into the popup toolbar item
- (void)reloadAddressBookMenu:(NSNotification *)aNotification
{
    NSToolbarItem *aToolbarItem = [self toolbarItemWithIdentifier:NewToolbarItem];

    if (aToolbarItem) {
        JournalParams params;
        params.selector = @selector(newSessionInTabAtIndex:);
        params.openAllSelector = @selector(newSessionsInWindow:);
        params.alternateSelector = @selector(newSessionInTabAtIndex:);
        params.alternateOpenAllSelector = @selector(newSessionsInWindow:);
        params.target = [iTermController sharedInstance];

        [BookmarkModel applyJournal:[aNotification userInfo] toMenu:iconMenu_ startingAtItem:1 params:&params];
        [BookmarkModel applyJournal:[aNotification userInfo] toMenu:textMenu_ params:&params];
    }
}

- (NSToolbarItem*)toolbarItemWithIdentifier:(NSString*)identifier
{
    NSArray *toolbarItemArray;
    NSToolbarItem *aToolbarItem;
    int i;

    toolbarItemArray = [_toolbar items];

    // Find the addressbook popup item and reset it
    for (i = 0; i < [toolbarItemArray count]; i++)
    {
        aToolbarItem = [toolbarItemArray objectAtIndex: i];

        if ([[aToolbarItem itemIdentifier] isEqual: identifier])
            return aToolbarItem;
    }

    return nil;
}


@end
