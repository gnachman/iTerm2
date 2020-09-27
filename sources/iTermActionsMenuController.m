//
//  iTermActionsMenuController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/8/20.
//

#import "iTermActionsMenuController.h"

#import "iTermController.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"

@implementation iTermActionsMenuController {
    IBOutlet NSMenuItem *_menu;
}

- (void)awakeFromNib {
    [iTermActionsDidChangeNotification subscribe:self selector:@selector(actionsDidChange:)];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(activeSessionDidChange:)
                                                 name:iTermSessionBecameKey
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileActionsDidChange:)
                                                 name:iTermProfileActionsDidChange
                                               object:nil];
    [self reload];
}

- (void)activeSessionDidChange:(NSNotification *)notification {
    [self reloadProfileActions];
}

- (void)reloadProfileActions {
    [self removeItemsForCurrentSession];
    [self addItemsForCurrentSession];
}

- (void)removeItemsForCurrentSession {
    NSInteger i = _menu.submenu.itemArray.count;
    i -= 1;
    while (i >= 0) {
        if (_menu.submenu.itemArray[i].tag == 1) {
            [_menu.submenu removeItemAtIndex:i];
        }
        i -= 1;
    }
}

- (void)addItemsForCurrentSession {
    if (_menu.submenu.itemArray.count > 0) {
        NSMenuItem *item = [NSMenuItem separatorItem];
        item.tag = 1;
        [_menu.submenu addItem:item];
    }
    PTYSession *session = [[[[iTermController sharedInstance] currentTerminal] currentTab] activeSession];
    [session.actions enumerateObjectsUsingBlock:
     ^(iTermAction * _Nonnull action, NSUInteger idx, BOOL * _Nonnull stop) {
        [self add:action profile:YES];
    }];
}

- (void)profileActionsDidChange:(NSNotification *)notification {
    PTYSession *session = [[[[iTermController sharedInstance] currentTerminal] currentTab] activeSession];
    if (![notification.object isEqual:session.profile[KEY_GUID]]) {
        return;
    }
    [self reloadProfileActions];
}

- (void)actionsDidChange:(iTermActionsDidChangeNotification *)notification {
    if (notification.model != [iTermActionsModel sharedInstance]) {
        return;
    }
    switch (notification.mutationType) {
        case iTermActionsDidChangeMutationTypeEdit:
            [self reloadIndex:notification.index];
            break;
        case iTermActionsDidChangeMutationTypeDeletion:
            [self deleteIndexes:notification.indexSet];
            break;
        case iTermActionsDidChangeMutationTypeInsertion:
            [self insertAtIndex:notification.index];
            break;
        case iTermActionsDidChangeMutationTypeMove:
            [self moveIndexes:notification.indexSet to:notification.index];
            break;
        case iTermActionsDidChangeMutationTypeFullReplacement:
            [self reload];
            break;
    }
}

- (void)reload {
    [_menu.submenu removeAllItems];
    [[[iTermActionsModel sharedInstance] actions] enumerateObjectsUsingBlock:
     ^(iTermAction * _Nonnull action, NSUInteger idx, BOOL * _Nonnull stop) {
        [self add:action profile:NO];
    }];
    [self addItemsForCurrentSession];
}

- (NSMenuItem *)menuItemForAction:(iTermAction *)action profile:(BOOL)profile {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:action.title
                                                  action:@selector(applyAction:)
                                           keyEquivalent:@""];
    item.tag = profile ? 1 : 0;
    item.representedObject = action;
    return item;
}

- (void)add:(iTermAction *)action profile:(BOOL)profile {
    [_menu.submenu addItem:[self menuItemForAction:action profile:profile]];
}

- (void)reloadIndex:(NSInteger)index {
    iTermAction *action = [[[iTermActionsModel sharedInstance] actions] objectAtIndex:index];
    NSMenuItem *item = [_menu.submenu itemAtIndex:index];
    item.title = action.title;
    item.representedObject = action;
}

- (void)deleteIndexes:(NSIndexSet *)indexes {
    [indexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        [_menu.submenu removeItemAtIndex:idx];
    }];
}

- (void)insertAtIndex:(NSInteger)index {
    iTermAction *action = [[iTermActionsModel sharedInstance] actions][index];
    [_menu.submenu insertItem:[self menuItemForAction:action profile:NO] atIndex:index];
    [self reloadIndex:index];
}

- (void)moveIndexes:(NSIndexSet *)sourceIndexes to:(NSInteger)destinationIndex {
    [self deleteIndexes:sourceIndexes];
    for (NSInteger i = 0; i < sourceIndexes.count; i++) {
        [self insertAtIndex:destinationIndex + i];
    }
}

@end
