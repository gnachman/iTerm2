//
//  iTermSessionTabWindowOutlineDelegate.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import "iTermSessionTabWindowOutlineDelegate.h"

#import "iTermController.h"
#import "iTermVariableScope.h"
#import "iTermVariablesOutlineDelegate.h"
#import "NSArray+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"

@interface iTermSessionTabWindowOutlineDelegate()<NSOutlineViewDataSource, NSOutlineViewDelegate>
@end

@protocol iTermOutlineProxy<NSObject>
@property (nonatomic, readonly) NSArray *children;
@property (nonatomic, readonly) BOOL isExpandable;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) iTermVariableScope *scope;
@end

@interface iTermOutlineSessionProxy : NSObject<iTermOutlineProxy>
@property (nonatomic, strong) PTYSession *session;
@end

@implementation iTermOutlineSessionProxy
- (instancetype)initWithSession:(PTYSession *)session {
    self = [super init];
    if (self) {
        _session = session;
    }
    return self;
}

- (BOOL)isExpandable {
    return NO;
}

- (NSArray *)children {
    return @[];
}

- (NSString *)displayName {
    return [NSString stringWithFormat:@"＞ %@ (%@)", _session.name, _session.guid];
}

- (iTermVariableScope *)scope {
    return _session.variablesScope;
}

@end

@interface iTermOutlineTabProxy : NSObject<iTermOutlineProxy>
@property (nonatomic, strong) PTYTab *tab;
@property (nonatomic, readonly) NSArray<iTermOutlineSessionProxy *> *children;
@end

@implementation iTermOutlineTabProxy
- (instancetype)initWithTab:(PTYTab *)tab {
    self = [super init];
    if (self) {
        _tab = tab;
        _children = [tab.sessions mapWithBlock:^id(PTYSession *session) {
            return [[iTermOutlineSessionProxy alloc] initWithSession:session];
        }];
    }
    return self;
}

- (BOOL)isExpandable {
    return YES;
}

- (NSString *)displayName {
    return [NSString stringWithFormat:@"📁 %@ (%@)", _tab.tabViewItem.label, @(_tab.uniqueId)];
}

- (iTermVariableScope *)scope {
    return _tab.variablesScope;
}

@end

@interface iTermOutlineWindowProxy : NSObject<iTermOutlineProxy>
@property (nonatomic, strong) PseudoTerminal *windowController;
@property (nonatomic, readonly) NSArray<iTermOutlineTabProxy *> *children;
@end

@implementation iTermOutlineWindowProxy
- (instancetype)initWithWindowController:(PseudoTerminal *)windowController {
    self = [super init];
    if (self) {
        _windowController = windowController;
        _children = [windowController.tabs mapWithBlock:^id(PTYTab *tab) {
            return [[iTermOutlineTabProxy alloc] initWithTab:tab];
        }];
    }
    return self;
}

- (BOOL)isExpandable {
    return YES;
}

- (NSString *)displayName {
    return [NSString stringWithFormat:@"🖼️ %@ (%@)", _windowController.window.title, _windowController.terminalGuid];
}

- (iTermVariableScope *)scope {
    return _windowController.scope;
}

@end

@interface iTermOutlineRoot : NSObject<iTermOutlineProxy>
@property (nonatomic, readonly) NSArray<iTermOutlineWindowProxy *> *children;
@end

@implementation iTermOutlineRoot
- (instancetype)init {
    self = [super init];
    if (self) {
        _children = [[[iTermController sharedInstance] terminals] mapWithBlock:^id(PseudoTerminal *windowController) {
            return [[iTermOutlineWindowProxy alloc] initWithWindowController:windowController];
        }];
    }
    return self;
}

- (BOOL)isExpandable {
    return YES;
}

- (NSString *)displayName {
    return @"iTerm2";
}

- (iTermVariableScope *)scope {
    return [iTermVariableScope globalsScope];
}

@end

@implementation iTermSessionTabWindowOutlineDelegate {
    IBOutlet NSOutlineView *_variablesOutlineView;
    iTermOutlineRoot *_root;
    iTermVariablesOutlineDelegate *_variablesOutlineDelegate;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _root = [[iTermOutlineRoot alloc] init];
    }
    return self;
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
    id<iTermOutlineProxy> proxy = item ?: _root;
    return proxy.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
    id<iTermOutlineProxy> proxy = item ?: _root;
    return proxy.children[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    id<iTermOutlineProxy> proxy = item ?: _root;
    return proxy.isExpandable;
}

#pragma mark - NSOutlineViewDelegate

// View Based OutlineView: See the delegate method -tableView:viewForTableColumn:row: in NSTableView.
- (nullable NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(nullable NSTableColumn *)tableColumn item:(id)item {
    id<iTermOutlineProxy> proxy = item;
    NSString *identifier = NSStringFromClass(proxy.class);
    NSTableCellView *view = [outlineView makeViewWithIdentifier:identifier owner:self];
    if (!view) {
        view = [[NSTableCellView alloc] init];

        NSTextField *textField = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        view.textField = textField;
        [view addSubview:textField];
        textField.frame = view.bounds;
        textField.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    }
    view.textField.stringValue = proxy.displayName;
    return view;

}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSLog(@"%@", notification);
    NSOutlineView *outlineView = notification.object;
    id<iTermOutlineProxy> proxy = [outlineView itemAtRow:outlineView.selectedRow];
    iTermVariableScope *scope = proxy.scope;
    if (scope) {
        _variablesOutlineDelegate = [[iTermVariablesOutlineDelegate alloc] initWithScope:scope];
        _variablesOutlineView.delegate = _variablesOutlineDelegate;
        _variablesOutlineView.dataSource = _variablesOutlineDelegate;
        [_variablesOutlineView reloadData];
    }
}

@end
