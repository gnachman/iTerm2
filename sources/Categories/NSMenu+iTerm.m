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

    for (NSMenuItem* item in [self itemArray]) {
        if (![item isEnabled] || [item isHidden]) {
            continue;
        }
        if ([item hasSubmenu]) {
            if ([item.submenu it_selectMenuItemWithTitle:title identifier:identifier]) {
                return YES;
            }
        }
        if ([ITAddressBookMgr shortcutIdentifier:identifier title:title matchesItem:item]) {
            if (item.hasSubmenu) {
                return YES;
            }
            [NSApp sendAction:[item action]
                           to:[item target]
                         from:item];
            return YES;
        }
    }
    return NO;
}


@end
