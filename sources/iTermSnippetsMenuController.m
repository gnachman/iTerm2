//
//  iTermSnippetsMenuController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/8/20.
//

#import "iTermSnippetsMenuController.h"

@implementation iTermSnippetsMenuController {
    IBOutlet NSMenuItem *_menuItem;
    NSMenu *_overridingMenu;  // If set, this takes priority over _menuItem
}

- (void)awakeFromNib {
    [iTermSnippetsDidChangeNotification subscribe:self selector:@selector(snippetsDidChange:)];
    [self reload];
}

- (void)snippetsDidChange:(iTermSnippetsDidChangeNotification *)notification {
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
        [self add:snippet];
    }];
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

- (void)add:(iTermSnippet *)snippet {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:snippet.title
                                                  action:@selector(sendSnippet:)
                                           keyEquivalent:@""];
    item.representedObject = snippet;
    [self.menu addItem:item];
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
    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.action = @selector(sendSnippet:);
    [self.menu insertItem:item atIndex:index];
    [self reloadIndex:index];
}

- (void)moveIndexes:(NSIndexSet *)sourceIndexes to:(NSInteger)destinationIndex {
    [self deleteIndexes:sourceIndexes];
    for (NSInteger i = 0; i < sourceIndexes.count; i++) {
        [self insertAtIndex:destinationIndex + i];
    }
}

@end
