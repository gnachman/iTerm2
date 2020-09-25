//
//  iTermSnippetsMenuController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/8/20.
//

#import "iTermSnippetsMenuController.h"

#import "iTermController.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"

@implementation iTermSnippetsMenuController {
    IBOutlet NSMenuItem *_menuItem;
    NSMenu *_overridingMenu;  // If set, this takes priority over _menuItem
}

- (void)awakeFromNib {
    [iTermSnippetsDidChangeNotification subscribe:self selector:@selector(snippetsDidChange:)];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(activeSessionDidChange:)
                                                 name:iTermSessionBecameKey
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileSnippetsDidChange:)
                                                 name:iTermProfileSnippetsDidChange
                                               object:nil];
    [self reload];
}

- (void)activeSessionDidChange:(NSNotification *)notification {
    [self reloadProfileSnippets];
}

- (void)reloadProfileSnippets {
    [self removeItemsForCurrentSession];
    [self addItemsForCurrentSession];
}

- (void)removeItemsForCurrentSession {
    NSInteger i = self.menu.itemArray.count;
    i -= 1;
    while (i >= 0) {
        if (self.menu.itemArray[i].tag == 1) {
            [self.menu removeItemAtIndex:i];
        }
        i -= 1;
    }
}

- (void)addItemsForCurrentSession {
    if (self.menu.itemArray.count > 0) {
        NSMenuItem *item = [NSMenuItem separatorItem];
        item.tag = 1;
        [self.menu addItem:item];
    }
    PTYSession *session = [[[[iTermController sharedInstance] currentTerminal] currentTab] activeSession];
    [session.snippets enumerateObjectsUsingBlock:
     ^(iTermSnippet * _Nonnull snippet, NSUInteger idx, BOOL * _Nonnull stop) {
        [self add:snippet profile:YES];
    }];
}

- (void)profileSnippetsDidChange:(NSNotification *)notification {
    PTYSession *session = [[[[iTermController sharedInstance] currentTerminal] currentTab] activeSession];
    if (![notification.object isEqual:session.profile[KEY_GUID]]) {
        return;
    }
    [self reloadProfileSnippets];
}

- (void)snippetsDidChange:(iTermSnippetsDidChangeNotification *)notification {
    if (notification.model != [iTermSnippetsModel sharedInstance]) {
        return;
    }
    switch (notification.mutationType) {
        case iTermSnippetsDidChangeMutationTypeEdit:
            [self reloadIndex:notification.index];
            break;
        case iTermSnippetsDidChangeMutationTypeDeletion:
            [self deleteIndexes:notification.indexSet];
            break;
        case iTermSnippetsDidChangeMutationTypeInsertion:
            [self insertAtIndex:notification.index];
            break;
        case iTermSnippetsDidChangeMutationTypeMove:
            [self moveIndexes:notification.indexSet to:notification.index];
            break;
        case iTermSnippetsDidChangeMutationTypeFullReplacement:
            [self reload];
            break;
    }
}

- (void)reload {
    [self.menu removeAllItems];
    [[[iTermSnippetsModel sharedInstance] snippets] enumerateObjectsUsingBlock:
     ^(iTermSnippet * _Nonnull snippet, NSUInteger idx, BOOL * _Nonnull stop) {
        [self add:snippet profile:NO];
    }];
    [self addItemsForCurrentSession];
}

- (NSMenu *)menu {
    if (_overridingMenu) {
        return _overridingMenu;
    }
    return _menuItem.submenu;
}

- (void)setMenu:(NSMenu *)menu {
    _overridingMenu = menu;
    [self reload];
}

- (NSMenuItem *)menuItemForSnippet:(iTermSnippet *)snippet profile:(BOOL)profile {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:snippet.title
                                                  action:@selector(sendSnippet:)
                                           keyEquivalent:@""];
    item.tag = profile ? 1 : 0;
    item.representedObject = snippet;
    return item;
}

- (void)add:(iTermSnippet *)snippet profile:(BOOL)profile {
    [self.menu addItem:[self menuItemForSnippet:snippet profile:profile]];
}

- (void)reloadIndex:(NSInteger)index {
    iTermSnippet *snippet = [[[iTermSnippetsModel sharedInstance] snippets] objectAtIndex:index];
    NSMenuItem *item = [self.menu itemAtIndex:index];
    item.title = snippet.title;
    item.representedObject = snippet;
}

- (void)deleteIndexes:(NSIndexSet *)indexes {
    [indexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        [self.menu removeItemAtIndex:idx];
    }];
}

- (void)insertAtIndex:(NSInteger)index {
    iTermSnippet *snippet = [[iTermSnippetsModel sharedInstance] snippets][index];
    [self.menu insertItem:[self menuItemForSnippet:snippet profile:NO]
                  atIndex:index];
    [self reloadIndex:index];
}

- (void)moveIndexes:(NSIndexSet *)sourceIndexes to:(NSInteger)destinationIndex {
    [self deleteIndexes:sourceIndexes];
    for (NSInteger i = 0; i < sourceIndexes.count; i++) {
        [self insertAtIndex:destinationIndex + i];
    }
}

@end
