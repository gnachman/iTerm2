//
//  NSPopUpButton+iTerm.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "NSPopUpButton+iTerm.h"
#import "ITAddressBookMgr.h"
#import "iTermColorPresets.h"
#import "iTermSnippetsModel.h"
#import "NSArray+iTerm.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "ProfileModel.h"

@implementation NSPopUpButton (iTerm)

- (void)populateWithProfilesSelectingGuid:(NSString*)selectedGuid
                             profileTypes:(ProfileType)profileTypes {
    int selectedIndex = 0;
    int i = 0;
    [self removeAllItems];
    NSArray* profiles = [[ProfileModel sharedInstance] bookmarks];
    for (Profile* profile in profiles) {
        if ((profile.profileType & profileTypes) == 0) {
            continue;
        }
        int j = 0;
        NSString* temp;
        do {
            if (j == 0) {
                temp = profile[KEY_NAME];
            } else {
                temp = [NSString stringWithFormat:@"%@ (%d)", profile[KEY_NAME], j];
            }
            j++;
        } while ([self indexOfItemWithTitle:temp] != -1);
        [self addItemWithTitle:temp];
        NSMenuItem* item = [self lastItem];
        [item setRepresentedObject:profile[KEY_GUID]];
        if ([[item representedObject] isEqualToString:selectedGuid]) {
            selectedIndex = i;
        }
        i++;
    }
    [self selectItemAtIndex:selectedIndex];
}

- (void)populateWithSnippetsSelectingActionKey:(id)actionKey {
    [self removeAllItems];
    NSArray *sorted = [[[iTermSnippetsModel sharedInstance] snippets] sortedArrayUsingComparator:^NSComparisonResult(iTermSnippet *lhs, iTermSnippet *rhs) {
        return [lhs.title localizedCaseInsensitiveCompare:rhs.title];
    }];
    __block NSInteger selectedIndex = -1;
    [sorted enumerateObjectsUsingBlock:^(iTermSnippet *snippet, NSUInteger i, BOOL * _Nonnull stop) {
        [self addItemWithTitle:snippet.displayTitle];
        NSMenuItem *item = self.lastItem;
        item.representedObject = snippet.actionKey;
        if ([snippet matchesActionKey:actionKey]) {
            selectedIndex = i;
        }
    }];
    if (selectedIndex != -1) {
        [self selectItemAtIndex:selectedIndex];
    }
}

- (void)loadColorPresetsSelecting:(NSString *)presetName {
    int selectedIndex = 0;
    [self removeAllItems];
    int i = 0;
    NSDictionary* presetsDict = [iTermColorPresets builtInColorPresets];
    for (NSString* key in  [[presetsDict allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [self addItemWithTitle:key];
        if ([key isEqualToString:presetName]) {
            selectedIndex = i;
        }
        i++;
    }

    NSDictionary* customPresets = [iTermColorPresets customColorPresets];
    if (customPresets && [customPresets count] > 0) {
        [self.menu addItem:[NSMenuItem separatorItem]];
        i++;
        for (NSString* key in  [[customPresets allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            [self addItemWithTitle:key];
            if ([key isEqualToString:presetName]) {
                selectedIndex = i;
            }
            i++;
        }
    }
    [self selectItemAtIndex:selectedIndex];
}

- (void)it_addItemWithTitle:(NSString *)title tag:(NSUInteger)tag {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    item.tag = tag;
    [self.menu addItem:item];
}

@end
