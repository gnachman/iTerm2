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
                                  params:(iTermProfileModelJournalParams *)params
                              identifier:(NSString *)identifier {
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
                                              params:params
                                          identifier:[identifier stringByAppendingFormat:@"/%@", suffix]];
        if (menuToAddOpenAll &&
            [self menuHasMultipleItemsExcludingAlternates:menuToAddOpenAll fromIndex:0] &&
            ![self menuHasOpenAll:menuToAddOpenAll]) {
            [self addOpenAllToMenu:menuToAddOpenAll params:params identifier:identifier];
        }
    }
    return submenu;
}

+ (void)addOpenAllToMenu:(NSMenu *)menu params:(iTermProfileModelJournalParams *)params identifier:(NSString *)identifier {
    // Add separator + open all menu items
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *openAll = [menu addItemWithTitle:@"Open All" action:params.openAllSelector keyEquivalent:@""];
    openAll.identifier = identifier ?: @"Open All";
    [openAll setTarget:params.target];

    // Add alternate open all menu
    NSMenuItem *altOpenAll = [[NSMenuItem alloc] initWithTitle:@"Open All in New Window"
                                                        action:params.alternateOpenAllSelector
                                                 keyEquivalent:@""];
    [altOpenAll setTarget:params.target];
    [altOpenAll setKeyEquivalentModifierMask:NSEventModifierFlagOption];
    [altOpenAll setAlternate:YES];
    [altOpenAll setRepresentedObject:gAltOpenAllRepresentedObject];
    altOpenAll.identifier = [identifier stringByAppendingString:@" (Alt)"] ?: @"Open All In New Window";
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
            withTag:(int)tag
         identifier:(NSString *)identifier {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[b objectForKey:KEY_NAME]
                                                  action:isAlternate ? params.alternateSelector : params.selector
                                           keyEquivalent:@""];
    [item setAlternate:isAlternate];
    item.identifier = [self concatenateIdentifier:identifier with:[self.class identifierForMenuItem:item]];
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
    if ([[NSString castFrom:b[KEY_CUSTOM_COMMAND]] isEqualToString:kProfilePreferenceCommandTypeCustomValue] ||
        [[NSString castFrom:b[KEY_CUSTOM_COMMAND]] isEqualToString:kProfilePreferenceCommandTypeSSHValue]) {
        item.toolTip = [NSString castFrom:b[KEY_COMMAND_LINE]] ?: @"";
    }
    [menu insertItem:item atIndex:pos];
}

- (NSString *)concatenateIdentifier:(NSString * _Nullable)first with:(NSString *)second {
    if (!first) {
        return second;
    }
    return [first stringByAppendingFormat:@"\t%@", second];
}

- (void)addBookmark:(Profile *)b
             toMenu:(NSMenu *)menu
     startingAtItem:(int)skip
           withTags:(NSArray *)tags
             params:(iTermProfileModelJournalParams *)params
              atPos:(int)theIndex
         identifier:(NSString *)identifier {
    int pos;
    if (theIndex == -1) {
        // Add in sorted order
        pos = [self positionOfBookmark:b startingAtItem:skip inMenu:menu];
    } else {
        pos = [self positionOfBookmarkWithIndex:theIndex startingAtItem:skip inMenu:menu];
    }

    if (![tags count]) {
        // Add item & alternate if no tags
        [self addBookmark:b toMenu:menu atPosition:pos withParams:params isAlternate:NO withTag:theIndex identifier:identifier];
        [self addBookmark:b toMenu:menu atPosition:pos+1 withParams:params isAlternate:YES withTag:theIndex identifier:identifier];
    }

    // Add to tag submenus
    for (NSString *tag in [NSSet setWithArray:tags]) {
        NSMenu *tagSubMenu = [self.class findOrCreateTagSubmenuInMenu:menu
                                                       startingAtItem:skip
                                                             withName:tag
                                                               params:params
                                                           identifier:[self concatenateIdentifier:identifier with:tag]];
        [self addBookmark:b
                   toMenu:tagSubMenu
           startingAtItem:0
                 withTags:nil
                   params:params
                    atPos:theIndex
               identifier:[self concatenateIdentifier:identifier with:tag]];
    }

    if ([[self class] menuHasMultipleItemsExcludingAlternates:menu fromIndex:skip] &&
        ![self.class menuHasOpenAll:menu]) {
        [self.class addOpenAllToMenu:menu params:params identifier:identifier];
    }
}

+ (NSString *)applyAddJournalEntry:(BookmarkJournalEntry *)e
                            toMenu:(NSMenu *)menu
                    startingAtItem:(int)skip
                            params:(iTermProfileModelJournalParams *)params {
    id<iTermProfileModelJournalModel> model = e.model;
    Profile *b = [NSDictionary castFrom:[model profileWithGuid:e.guid]];
    if (!b) {
        return nil;
    }
    [model.menuController addBookmark:b
                               toMenu:menu
                       startingAtItem:skip
                             withTags:b[KEY_TAGS]
                               params:params
                                atPos:e.index
                           identifier:nil];
    return [b[KEY_SHORTCUT] uppercaseString];
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

+ (NSString *)applyRemoveJournalEntry:(BookmarkJournalEntry *)e
                               toMenu:(NSMenu *)menu
                       startingAtItem:(int)skip
                               params:(iTermProfileModelJournalParams *)params {
    int pos = [menu indexOfItemWithRepresentedObject:e.guid];
    NSString *shortcut = nil;
    if (pos != -1) {
        NSMenuItem *item = [menu itemAtIndex:pos];
        shortcut = [item.keyEquivalent uppercaseString];
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
    return shortcut;
}

+ (NSSet<NSString *> *)applyRemoveAllJournalEntry:(BookmarkJournalEntry *)e
                                           toMenu:(NSMenu *)menu
                                   startingAtItem:(int)skip
                                           params:(iTermProfileModelJournalParams *)params {
    NSMutableSet<NSString *> *results = [NSMutableSet set];
    while ([menu numberOfItems] > skip) {
        NSMenuItem *itemToRemove = menu.itemArray.lastObject;
        NSString *shortcut = [itemToRemove keyEquivalent];
        if (shortcut) {
            [results addObject:shortcut];
        }
        [menu removeItemAtIndex:[menu numberOfItems] - 1];
    }
    return results;
}

+ (void)applySetDefaultJournalEntry:(BookmarkJournalEntry *)e
                             toMenu:(NSMenu *)menu
                     startingAtItem:(int)skip
                             params:(iTermProfileModelJournalParams *)params {
}

+ (NSDictionary<NSString *, NSNumber *> *)applyJournal:(NSDictionary *)journalDict
                                                toMenu:(NSMenu *)menu
                                        startingAtItem:(int)skip
                                                params:(iTermProfileModelJournalParams *)params {
    NSArray *journal = [journalDict objectForKey:@"array"];
    NSMutableDictionary<NSString *, NSNumber *> *results = [NSMutableDictionary dictionary];
    for (BookmarkJournalEntry *e in journal) {
        switch (e.action) {
            case JOURNAL_ADD: {
                NSString *shortcut = [self.class applyAddJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                if (shortcut) {
                    results[shortcut] = @YES;
                }
                break;
            }

            case JOURNAL_REMOVE: {
                NSString *shortcut = [self.class applyRemoveJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                if (shortcut) {
                    results[shortcut] = @NO;
                }
                break;
            }

            case JOURNAL_REMOVE_ALL: {
                NSSet<NSString *> *shortcuts = [self.class applyRemoveAllJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                for (NSString *shortcut in shortcuts) {
                    [results removeObjectForKey:shortcut];
                }
                break;
            }

            case JOURNAL_SET_DEFAULT:
                [self.class applySetDefaultJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                break;

            default:
                assert(false);
        }
    }
    return results;
}

@end
