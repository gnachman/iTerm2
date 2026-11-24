//
//  NSMenu+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 6/25/25.
//

#import "NSMenu+iTerm.h"

#import "DebugLogging.h"
#import "PTYWindow.h"
#import "NSScreen+iTerm.h"
#import "ITAddressBookMgr.h"
#import "iTerm2SharedARC-Swift.h"

@interface NSMenu (iTermAdditionsPrivate)
- (BOOL)it_moveToScreenWithIdentifier:(NSString * _Nullable)identifier;
- (NSMenuItem *)it_resolveMenuItemWithTitle:(NSString * _Nullable)title identifier:(NSString * _Nullable)identifier;
- (NSMenuItem *)it_firstSelectableItemPassingTest:(BOOL (^)(NSMenuItem *))test refresh:(BOOL)refresh;
- (NSMenuItem *)it_firstItemPassingTest:(BOOL (^)(NSMenuItem *))test;
@end

@implementation NSMenu(iTermAdditions)

- (BOOL)it_selectMenuItemWithTitle:(NSString * _Nullable)title identifier:(NSString * _Nullable)identifier {
    [self update];

    // A screen's unique key names no menu item, so trying it first cannot take a binding away
    // from a real item.
    if ([self it_moveToScreenWithIdentifier:identifier]) {
        return YES;
    }

    // Do not resolve the reference again in each submenu on failure: a submenu cannot know
    // that the identifier names a live item in a different submenu, so it would use the title
    // fallback and fire an unrelated item with the same title.
    NSMenuItem *target = [self it_resolveMenuItemWithTitle:title identifier:identifier];
    if (!target) {
        return NO;
    }
    if (target.hasSubmenu) {
        return YES;
    }
    // A user-defined Action that selects a menu item can name its own entry in the Actions menu,
    // or several can form a cycle. Firing an item that is already firing would recurse until the
    // stack overflows.
    static NSMutableSet<NSValue *> *firing;
    if (!firing) {
        firing = [[NSMutableSet alloc] init];
    }
    NSValue *key = [NSValue valueWithNonretainedObject:target];
    if ([firing containsObject:key]) {
        DLog(@"Refusing to recursively select menu item %@", target.title);
        return NO;
    }
    [firing addObject:key];
    [NSApp sendAction:[target action]
                   to:[target target]
                 from:target];
    [firing removeObject:key];
    return YES;
}

// The Window menu has "Move to <screen>" items that a binding stores by the unique key of the
// screen. Find the Window menu in this subtree and move the key window.
- (BOOL)it_moveToScreenWithIdentifier:(NSString * _Nullable)identifier {
    if (![NSScreen it_stringLooksLikeUniqueKey:identifier]) {
        return NO;
    }
    if (self == [NSApp windowsMenu]) {
        if (![[NSApp keyWindow] respondsToSelector:@selector(_moveToScreen:)]) {
            return NO;
        }
        NSScreen *screen = [NSScreen it_screenWithUniqueKey:identifier];
        if (!screen) {
            return NO;
        }
        [NSApp sendAction:@selector(_moveToScreen:) to:nil from:screen];
        return YES;
    }
    for (NSMenuItem *item in [self itemArray]) {
        if (![item isEnabled] || [item isHidden] || ![item hasSubmenu]) {
            continue;
        }
        if ([item.submenu it_moveToScreenWithIdentifier:identifier]) {
            return YES;
        }
    }
    return NO;
}

// Resolve a stored (title, identifier) reference to a single live menu item across this
// menu's whole subtree in document order. An identifier resolves first: a stable identifier,
// or a synthetic "_NS:<n>" that still names a live item, wins over any title match. If no
// identifier resolves we fall back to title and fire the FIRST document-order match, walking
// both leaves and submenus. Legacy title-only bindings can be ambiguous when duplicated (e.g.
// Session > Reset vs Terminal State > Reset); master fired the first such item, so we do too
// rather than fail closed and fire nothing (or an arbitrary nested duplicate).
//
// The title fallback is only for an identifier that names no live item. When the identifier
// names an item that is disabled or hidden, and the identifier is stable (not "_NS:<n>"),
// the reference is not stale: the user asked for
// that item and it is not available now. Resolve to nil. A title match there would fire an
// unrelated item with the same title, such as a user-defined action in Edit > Actions that
// has the title of the menu item that it selects.
- (NSMenuItem *)it_resolveMenuItemWithTitle:(NSString * _Nullable)title identifier:(NSString * _Nullable)identifier {
    BOOL (^matchesIdentifier)(NSMenuItem *) = ^BOOL(NSMenuItem *item) {
        return [ITAddressBookMgr shortcutIdentifier:identifier title:nil matchesItem:item];
    };
    NSMenuItem *byIdentifier = [self it_firstSelectableItemPassingTest:matchesIdentifier refresh:YES];
    if (byIdentifier) {
        return byIdentifier;
    }
    // Only a stable identifier proves which item the user meant. A synthetic "_NS:<n>" is
    // positional, so after a relaunch or a menu rebuild it can name an unrelated item. Those
    // legacy bindings keep the title fallback.
    if ([iTermMenuItemBinding normalizedStoredIdentifier:identifier] &&
        [self it_firstItemPassingTest:matchesIdentifier]) {
        return nil;
    }
    if (title.length == 0) {
        return nil;
    }
    // The first walk visited the same submenus and refreshed them.
    return [self it_firstSelectableItemPassingTest:^BOOL(NSMenuItem *item) {
        return [ITAddressBookMgr shortcutIdentifier:nil title:title matchesItem:item];
    } refresh:NO];
}

// -[NSMenu update] validates only the items of the receiver, not the items of its submenus.
// With refresh, update each submenu before the walk goes into it, so that isEnabled is
// correct now and not the value from the last time that the submenu was open.
- (NSMenuItem *)it_firstSelectableItemPassingTest:(BOOL (^)(NSMenuItem *))test refresh:(BOOL)refresh {
    for (NSMenuItem *item in [self itemArray]) {
        if (![item isEnabled] || [item isHidden]) {
            continue;
        }
        if (test(item)) {
            return item;
        }
        if ([item hasSubmenu]) {
            if (refresh) {
                [item.submenu update];
            }
            NSMenuItem *hit = [item.submenu it_firstSelectableItemPassingTest:test refresh:refresh];
            if (hit) {
                return hit;
            }
        }
    }
    return nil;
}

// Like it_firstSelectableItemPassingTest:refresh: but it also visits disabled and hidden items.
- (NSMenuItem *)it_firstItemPassingTest:(BOOL (^)(NSMenuItem *))test {
    for (NSMenuItem *item in [self itemArray]) {
        if (test(item)) {
            return item;
        }
        if ([item hasSubmenu]) {
            NSMenuItem *hit = [item.submenu it_firstItemPassingTest:test];
            if (hit) {
                return hit;
            }
        }
    }
    return nil;
}

- (NSMenuItem *)it_itemWithIdentifier:(NSString *)identifier {
    for (NSMenuItem *item in [self itemArray]) {
        if ([item.identifier isEqualToString:identifier]) {
            return item;
        }
    }
    return nil;
}


@end
