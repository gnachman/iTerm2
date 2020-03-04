//
//  iTermProfilesMenuController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/20.
//

#import "iTermProfilesMenuController.h"

#import "ITAddressBookMgr.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermProfilesMenuController

static id gAltOpenAllRepresentedObject;

+ (void)initialize {
    gAltOpenAllRepresentedObject = [[NSObject alloc] init];
}


+ (BOOL)menuHasMultipleItemsExcludingAlternates:(NSMenu *)menu fromIndex:(int)first {
    int n = 0;
    for (NSMenuItem *item in menu.itemArray) {
        if (!item.isAlternate) {
            n++;
            if (n == 2) {
                return YES;
            }
        }
    }
    return NO;
}

+ (NSMenu *)findOrCreateTagSubmenuInMenu:(NSMenu *)menu
                          startingAtItem:(int)skip
                                withName:(NSString *)multipartName
                                  params:(iTermProfileModelJournalParams *)params {
    NSArray *parts = [multipartName componentsSeparatedByString:@"/"];
    if (parts.count == 0) {
        return nil;
    }
    NSString *name = parts[0];
    NSArray *items = [menu itemArray];
    int pos = [menu numberOfItems];
    int N = pos;
    NSMenu *submenu = nil;
    for (int i = skip; i < N; i++) {
        NSMenuItem *cur = [items objectAtIndex:i];
        if (![cur submenu] || [cur isSeparatorItem]) {
            pos = i;
            break;
        }
        int comp = [[cur title] caseInsensitiveCompare:name];
        if (comp == 0) {
            submenu = [cur submenu];
            break;
        } else if (comp > 0) {
            pos = i;
            break;
        }
    }

    if (!submenu) {
        // Add menu item with submenu
        NSMenuItem *newItem = [[NSMenuItem alloc] initWithTitle:name
                                                         action:nil
                                                  keyEquivalent:@""];
        [newItem setSubmenu:[[NSMenu alloc] init]];
        [menu insertItem:newItem atIndex:pos];
        submenu = [newItem submenu];
    }

    if (parts.count > 1) {
        NSArray *tail = [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)];
        NSString *suffix = [tail componentsJoinedByString:@"/"];
        NSMenu *menuToAddOpenAll = submenu;
        submenu = [self findOrCreateTagSubmenuInMenu:submenu
                                      startingAtItem:0
                                            withName:suffix
                                              params:params];
        if (menuToAddOpenAll &&
            [self menuHasMultipleItemsExcludingAlternates:menuToAddOpenAll fromIndex:0] &&
            ![self menuHasOpenAll:menuToAddOpenAll]) {
            [self addOpenAllToMenu:menuToAddOpenAll params:params];
        }
    }
    return submenu;
}

+ (void)addOpenAllToMenu:(NSMenu *)menu params:(iTermProfileModelJournalParams *)params {
    // Add separator + open all menu items
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *openAll = [menu addItemWithTitle:@"Open All" action:params.openAllSelector keyEquivalent:@""];
    [openAll setTarget:params.target];

    // Add alternate open all menu
    NSMenuItem *altOpenAll = [[NSMenuItem alloc] initWithTitle:@"Open All in New Window"
                                                        action:params.alternateOpenAllSelector
                                                 keyEquivalent:@""];
    [altOpenAll setTarget:params.target];
    [altOpenAll setKeyEquivalentModifierMask:NSEventModifierFlagOption];
    [altOpenAll setAlternate:YES];
    [altOpenAll setRepresentedObject:gAltOpenAllRepresentedObject];
    [menu addItem:altOpenAll];
}

+ (BOOL)menuHasOpenAll:(NSMenu *)menu {
    NSArray *items = [menu itemArray];
    if (items.count < 3) {
        return NO;
    }
    int n = [items count];
    return ([items[n-1] representedObject] == gAltOpenAllRepresentedObject);
}

- (int)positionOfBookmark:(Profile *)b startingAtItem:(int)skip inMenu:(NSMenu *)menu {
    // Find position of bookmark in menu
    NSString *name = b[KEY_NAME];
    int N = [menu numberOfItems];
    if ([self.class menuHasOpenAll:menu]) {
        N -= 3;
    }
    NSArray *items = [menu itemArray];
    int pos = N;
    for (int i = skip; i < N; i++) {
        NSMenuItem *cur = [items objectAtIndex:i];
        if ([cur isSeparatorItem]) {
            break;
        }
        if ([cur isHidden] || [cur submenu]) {
            continue;
        }
        if ([[cur title] caseInsensitiveCompare:name] > 0) {
            pos = i;
            break;
        }
    }

    return pos;
}

- (int)positionOfBookmarkWithIndex:(int)theIndex startingAtItem:(int)skip inMenu:(NSMenu *)menu {
    // Find position of bookmark in menu
    int N = [menu numberOfItems];
    if ([self.class menuHasOpenAll:menu]) {
        N -= 3;
    }
    NSArray *items = [menu itemArray];
    int pos = N;
    for (int i = skip; i < N; i++) {
        NSMenuItem *cur = [items objectAtIndex:i];
        if ([cur isSeparatorItem]) {
            break;
        }
        if ([cur isHidden] || [cur submenu]) {
            continue;
        }
        if ([cur tag] > theIndex) {
            pos = i;
            break;
        }
    }

    return pos;
}

+ (NSString *)identifierForMenuItem:(NSMenuItem *)item {
    NSString *prefix = item.isAlternate ? iTermProfileModelNewWindowMenuItemIdentifierPrefix : iTermProfileModelNewTabMenuItemIdentifierPrefix;
    return [prefix stringByAppendingString:item.title];
}

- (void)addBookmark:(Profile *)b
             toMenu:(NSMenu *)menu
         atPosition:(int)pos
         withParams:(iTermProfileModelJournalParams *)params
        isAlternate:(BOOL)isAlternate
            withTag:(int)tag {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[b objectForKey:KEY_NAME]
                                                  action:isAlternate ? params.alternateSelector : params.selector
                                           keyEquivalent:@""];
    [item setAlternate:isAlternate];
    item.identifier = [self.class identifierForMenuItem:item];
    NSString *shortcut = [NSString castFrom:[b objectForKey:KEY_SHORTCUT]];
    if ([shortcut length]) {
        [item setKeyEquivalent:[shortcut lowercaseString]];
        [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagControl | (isAlternate ? NSEventModifierFlagOption : 0)];
    } else if (isAlternate) {
        [item setKeyEquivalentModifierMask:NSEventModifierFlagOption];
    }
    [item setTarget:params.target];
    NSString *guid = [NSString castFrom:[b objectForKey:KEY_GUID]] ?: [[NSUUID UUID] UUIDString];
    [item setRepresentedObject:[guid copy]];
    [item setTag:tag];
    if ([[NSString castFrom:b[KEY_CUSTOM_COMMAND]] isEqualToString:kProfilePreferenceCommandTypeCustomValue]) {
        item.toolTip = [NSString castFrom:b[KEY_COMMAND_LINE]] ?: @"";
    }
    [menu insertItem:item atIndex:pos];
}

- (void)addBookmark:(Profile *)b
             toMenu:(NSMenu *)menu
     startingAtItem:(int)skip
           withTags:(NSArray *)tags
             params:(iTermProfileModelJournalParams *)params
              atPos:(int)theIndex {
    int pos;
    if (theIndex == -1) {
        // Add in sorted order
        pos = [self positionOfBookmark:b startingAtItem:skip inMenu:menu];
    } else {
        pos = [self positionOfBookmarkWithIndex:theIndex startingAtItem:skip inMenu:menu];
    }

    if (![tags count]) {
        // Add item & alternate if no tags
        [self addBookmark:b toMenu:menu atPosition:pos withParams:params isAlternate:NO withTag:theIndex];
        [self addBookmark:b toMenu:menu atPosition:pos+1 withParams:params isAlternate:YES withTag:theIndex];
    }

    // Add to tag submenus
    for (NSString *tag in [NSSet setWithArray:tags]) {
        NSMenu *tagSubMenu = [self.class findOrCreateTagSubmenuInMenu:menu
                                                       startingAtItem:skip
                                                             withName:tag
                                                               params:params];
        [self addBookmark:b toMenu:tagSubMenu startingAtItem:0 withTags:nil params:params atPos:theIndex];
    }

    if ([[self class] menuHasMultipleItemsExcludingAlternates:menu fromIndex:skip] &&
        ![self.class menuHasOpenAll:menu]) {
        [self.class addOpenAllToMenu:menu params:params];
    }
}

+ (void)applyAddJournalEntry:(BookmarkJournalEntry *)e
                      toMenu:(NSMenu *)menu
              startingAtItem:(int)skip
                      params:(iTermProfileModelJournalParams *)params {
    id<iTermProfileModelJournalModel> model = e.model;
    Profile *b = [NSDictionary castFrom:[model profileWithGuid:e.guid]];
    if (!b) {
        return;
    }
    [model.menuController addBookmark:b
                               toMenu:menu
                       startingAtItem:skip
                             withTags:b[KEY_TAGS]
                               params:params
                                atPos:e.index];
}

+ (NSArray *)menuItemsForTag:(NSString *)multipartName inMenu:(NSMenu *)menu {
    NSMutableArray *result = [NSMutableArray array];
    NSArray *parts = [multipartName componentsSeparatedByString:@"/"];
    NSMenuItem *item = nil;
    for (NSString *name in parts) {
        item = [menu itemWithTitle:name];
        if (!item) {
            break;
        }
        [result addObject:item];
        menu = [item submenu];
    }
    return result;
}

+ (void)applyRemoveJournalEntry:(BookmarkJournalEntry *)e
                         toMenu:(NSMenu *)menu
                 startingAtItem:(int)skip
                         params:(iTermProfileModelJournalParams *)params {
    int pos = [menu indexOfItemWithRepresentedObject:e.guid];
    if (pos != -1) {
        [menu removeItemAtIndex:pos];
        [menu removeItemAtIndex:pos];
    }

    // Remove bookmark from each tag it belongs to
    for (NSString *tag in e.tags) {
        NSArray *items = [self menuItemsForTag:tag inMenu:menu];
        for (int i = items.count - 1; i >= 0; i--) {
            NSMenuItem *item = items[i];
            NSMenu *submenu = [item submenu];
            if (submenu) {
                if (i == items.count - 1) {
                    [self applyRemoveJournalEntry:e toMenu:submenu startingAtItem:0 params:params];
                }
                if ([submenu numberOfItems] == 0) {
                    [[[item parentItem] submenu] removeItem:item];

                    // Remove "open all" (not at first level)
                    if ([self.class menuHasOpenAll:submenu] && submenu.numberOfItems <= 5) {
                        [menu removeItemAtIndex:[menu numberOfItems] - 1];
                        [menu removeItemAtIndex:[menu numberOfItems] - 1];
                        [menu removeItemAtIndex:[menu numberOfItems] - 1];
                    }
                } else {
                    break;
                }
            }
        }
    }

    // Remove "open all" section if it's no longer needed.
    // [0, ..., skip-1, bm1, bm1alt, separator, open all, open all alternate]
    if (([self.class menuHasOpenAll:menu] && [menu numberOfItems] <= skip + 5)) {
        [menu removeItemAtIndex:[menu numberOfItems] - 1];
        [menu removeItemAtIndex:[menu numberOfItems] - 1];
        [menu removeItemAtIndex:[menu numberOfItems] - 1];
    }
}

+ (void)applyRemoveAllJournalEntry:(BookmarkJournalEntry *)e
                            toMenu:(NSMenu *)menu
                    startingAtItem:(int)skip
                            params:(iTermProfileModelJournalParams *)params {
    while ([menu numberOfItems] > skip) {
        [menu removeItemAtIndex:[menu numberOfItems] - 1];
    }
}

+ (void)applySetDefaultJournalEntry:(BookmarkJournalEntry *)e
                             toMenu:(NSMenu *)menu
                     startingAtItem:(int)skip
                             params:(iTermProfileModelJournalParams *)params {
}

+ (void)applyJournal:(NSDictionary *)journalDict
              toMenu:(NSMenu *)menu
      startingAtItem:(int)skip
              params:(iTermProfileModelJournalParams *)params {
    NSArray *journal = [journalDict objectForKey:@"array"];
    for (BookmarkJournalEntry *e in journal) {
        switch (e.action) {
            case JOURNAL_ADD:
                [self.class applyAddJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                break;

            case JOURNAL_REMOVE:
                [self.class applyRemoveJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                break;

            case JOURNAL_REMOVE_ALL:
                [self.class applyRemoveAllJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                break;

            case JOURNAL_SET_DEFAULT:
                [self.class applySetDefaultJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                break;

            default:
                assert(false);
        }
    }
}

+ (void)applyJournal:(NSDictionary *)journal
              toMenu:(NSMenu *)menu
              params:(iTermProfileModelJournalParams *)params {
    [self.class applyJournal:journal
                      toMenu:menu
              startingAtItem:0
                      params:params];
}

@end
