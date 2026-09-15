//
//  NSMenu+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 6/25/25.
//

#import "NSMenu+iTerm.h"
#import "PTYWindow.h"
#import "NSScreen+iTerm.h"
#import "ITAddressBookMgr.h"

@interface NSMenu (iTermAdditionsPrivate)
- (NSMenuItem *)it_resolveMenuItemWithTitle:(NSString * _Nullable)title identifier:(NSString * _Nullable)identifier;
- (NSMenuItem *)it_firstSelectableItemPassingTest:(BOOL (^)(NSMenuItem *))test;
@end

@implementation NSMenu(iTermAdditions)

- (BOOL)it_selectMenuItemWithTitle:(NSString * _Nullable)title identifier:(NSString * _Nullable)identifier {
    [self update];

    if (self == [NSApp windowsMenu] &&
        [[NSApp keyWindow] respondsToSelector:@selector(_moveToScreen:)] &&
        [NSScreen it_stringLooksLikeUniqueKey:identifier]) {
        NSScreen *screen = [NSScreen it_screenWithUniqueKey:identifier];
        if (screen) {
            [NSApp sendAction:@selector(_moveToScreen:) to:nil from:screen];
            return YES;
        }
    }

    NSMenuItem *target = [self it_resolveMenuItemWithTitle:title identifier:identifier];
    if (!target) {
        // Preserve the recursive move-to-screen handling for descendant Window menus.
        for (NSMenuItem *item in [self itemArray]) {
            if (![item isEnabled] || [item isHidden] || ![item hasSubmenu]) {
                continue;
            }
            if ([item.submenu it_selectMenuItemWithTitle:title identifier:identifier]) {
                return YES;
            }
        }
        return NO;
    }
    if (target.hasSubmenu) {
        return YES;
    }
    [NSApp sendAction:[target action]
                   to:[target target]
                 from:target];
    return YES;
}

// Resolve a stored (title, identifier) reference to a single live menu item across this
// menu's whole subtree in document order. An identifier resolves first: a stable identifier,
// or a synthetic "_NS:<n>" that still names a live item, wins over any title match. If no
// identifier resolves we fall back to title and fire the FIRST document-order match, walking
// both leaves and submenus. Legacy title-only bindings can be ambiguous when duplicated (e.g.
// Session > Reset vs Terminal State > Reset); master fired the first such item, so we do too
// rather than fail closed and fire nothing (or an arbitrary nested duplicate).
- (NSMenuItem *)it_resolveMenuItemWithTitle:(NSString * _Nullable)title identifier:(NSString * _Nullable)identifier {
    NSMenuItem *byIdentifier = [self it_firstSelectableItemPassingTest:^BOOL(NSMenuItem *item) {
        return [ITAddressBookMgr shortcutIdentifier:identifier title:nil matchesItem:item];
    }];
    if (byIdentifier) {
        return byIdentifier;
    }
    if (title.length == 0) {
        return nil;
    }
    return [self it_firstSelectableItemPassingTest:^BOOL(NSMenuItem *item) {
        return [ITAddressBookMgr shortcutIdentifier:nil title:title matchesItem:item];
    }];
}

- (NSMenuItem *)it_firstSelectableItemPassingTest:(BOOL (^)(NSMenuItem *))test {
    for (NSMenuItem *item in [self itemArray]) {
        if (![item isEnabled] || [item isHidden]) {
            continue;
        }
        if (test(item)) {
            return item;
        }
        if ([item hasSubmenu]) {
            NSMenuItem *hit = [item.submenu it_firstSelectableItemPassingTest:test];
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
