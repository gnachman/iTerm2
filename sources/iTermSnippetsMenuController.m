//
//  iTermSnippetsMenuController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/8/20.
//

#import "iTermSnippetsMenuController.h"
#import "iTermController.h"
#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermSnippetsMenuController {
    IBOutlet NSMenuItem *_menuItem;
    NSMenu *_overridingMenu;  // If set, this takes priority over _menuItem
    NSArray<NSString *> *_tags;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(bogus)) {
        return NO;
    }
    return YES;
}

- (void)awakeFromNib {
    [iTermSnippetsDidChangeNotification subscribe:self selector:@selector(snippetsDidChange:)];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(snippetsTagsDidChange:)
                                                 name:iTermSnippetsTagsDidChange
                                               object:nil];
    [self reload];
}

- (void)snippetsTagsDidChange:(NSNotification *)notification {
    [self checkForTagsChange];
}

- (BOOL)checkForTagsChange {
    NSArray<NSString *> *tags = [[iTermController sharedInstance] currentSnippetsFilter];
    if (![NSObject object:tags isEqualToObject:_tags]) {
        DLog(@"Tags changed from %@ to %@", _tags, tags);
        [self reload];
        return YES;
    }
    return NO;
}

- (void)snippetsDidChange:(iTermSnippetsDidChangeNotification *)notification {
    [self reload];
}

- (void)reload {
    [self.menu removeAllItems];
    [self.menu addItemWithTitle:@"Press Option to Edit Before Sending" action:@selector(bogus) keyEquivalent:@""];
    [self.menu addItem:[NSMenuItem separatorItem]];

    NSMutableArray *tagTree = [NSMutableArray array];
    _tags = [[iTermController sharedInstance] currentSnippetsFilter];
    [[[iTermSnippetsModel sharedInstance] snippets] enumerateObjectsUsingBlock:
     ^(iTermSnippet * _Nonnull snippet, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([snippet hasTags:_tags]) {
            [self add:snippet];
            if (snippet.tags) {
                [self addTags:snippet.tags snippet:snippet toTree:tagTree];
            }
        }
    }];
    if (tagTree.count) {
        [self.menu addItem:[NSMenuItem separatorItem]];
        [self addTree:tagTree toMenu:self.menu path:@[]];
    }
}

- (void)addTree:(NSArray *)tree toMenu:(NSMenu *)menu path:(NSArray<NSString *> *)path {
    NSArray *sortedNodes = [tree sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        return [lhs[@"tag"] compare:rhs[@"tag"]];
    }];
    [sortedNodes enumerateObjectsUsingBlock:^(NSDictionary *node, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *name = node[@"tag"];
        NSMutableArray *container = node[@"container"];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name action:nil keyEquivalent:@""];
        [menu addItem:item];
        item.submenu = [[NSMenu alloc] init];
        if (container.count > 0) {
            [self addTree:container toMenu:item.submenu path:[path arrayByAddingObject:name]];
        }
        NSArray<iTermSnippet *> *snippets = node[@"snippets"];
        snippets = [snippets sortedArrayUsingSelector:@selector(compareTitle:)];
        if (container.count > 0 && snippets.count > 0) {
            [item.submenu addItem:[NSMenuItem separatorItem]];
        }
        [snippets enumerateObjectsUsingBlock:^(iTermSnippet *snippet, NSUInteger idx, BOOL * _Nonnull stop) {
            [self addSnippet:snippet toMenu:item.submenu];
        }];
    }];
}

- (void)addSnippet:(iTermSnippet *)snippet toMenu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:snippet.displayTitle
                                                  action:@selector(sendSnippet:)
                                           keyEquivalent:@""];
    item.representedObject = snippet;
    [menu addItem:item];
}

- (void)addTags:(NSArray<NSString *> *)tags snippet:(iTermSnippet *)snippet toTree:(NSMutableArray *)tree {
    [tags enumerateObjectsUsingBlock:^(NSString * _Nonnull tag, NSUInteger idx, BOOL * _Nonnull stop) {
        [self addTagComponents:[tag componentsSeparatedByString:@"/"]
                       snippet:snippet
                        toTree:tree];
    }];
}

- (id)nodeForFolderNamed:(NSString *)name {
    return @{ @"tag": name, @"container": [NSMutableArray array] };
}

- (id)nodeForTagNamed:(NSString *)name snippet:(iTermSnippet *)snippet {
    return @{ @"tag": name, @"snippets": @[snippet].mutableCopy, @"container": [NSMutableArray array] };
}

- (void)addTagComponents:(NSArray<NSString *> *)components
                 snippet:(iTermSnippet *)snippet
                  toTree:(NSMutableArray *)tree {
    if (components.count == 1) {
        NSDictionary *entry = [tree objectPassingTest:^BOOL(NSDictionary *element, NSUInteger index, BOOL *stop) {
            return [element[@"tag"] isEqual:components[0]];
        }];
        if (entry) {
            NSMutableArray *snippets = entry[@"snippets"];
            [snippets addObject:snippet];
        } else {
            [tree addObject:[self nodeForTagNamed:components[0] snippet:snippet]];
        }
    } else {
        NSString *folderName = components[0];
        NSDictionary *child = [tree objectPassingTest:^BOOL(NSDictionary *element, NSUInteger index, BOOL *stop) {
            return [element[@"tag"] isEqual:folderName];
        }];
        NSMutableArray *container;
        id node = [self nodeForFolderNamed:folderName];
        if (!child) {
            [tree addObject:node];
            container = node[@"container"];
        } else {
            container = child[@"container"];
        }
        [self addTagComponents:[components subarrayFromIndex:1] 
                       snippet:snippet
                        toTree:container];
    }
}

- (IBAction)bogus {
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
    [self addSnippet:snippet toMenu:self.menu];
}

@end
