//
//  iTermSessionTabWindowOutlineDelegate.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import "iTermSessionTabWindowOutlineDelegate.h"

#import "iTermBuriedSessions.h"
#import "iTermController.h"
#import "iTermSessionPicker.h"
#import "iTermVariableScope+Global.h"
#import "iTermVariablesOutlineDelegate.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"
#import "SessionView.h"

@interface iTermSessionTabWindowOutlineDelegate()<NSOutlineViewDataSource, NSOutlineViewDelegate>
@end

@protocol iTermOutlineProxy<NSObject>
@property (nonatomic, readonly) NSArray *children;
@property (nonatomic, readonly) BOOL isExpandable;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) iTermVariableScope *scope;
@property (nonatomic, readonly) id identifier;
- (void)reveal;
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

- (id)identifier {
    return _session.guid;
}

- (void)reveal {
    [_session reveal];
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
    return [NSString stringWithFormat:@"🗂 %@ (%@)", _tab.tabViewItem.label, @(_tab.uniqueId)];
}

- (iTermVariableScope *)scope {
    return _tab.variablesScope;
}

- (id)identifier {
    return [@(_tab.uniqueId) stringValue];
}

- (void)reveal {
    [_tab.activeSession reveal];
}

@end

@interface iTermOutlineBuriedSessionsProxy : NSObject<iTermOutlineProxy>
@property (nonatomic, readonly) NSArray<iTermOutlineSessionProxy *> *children;
@end

@implementation iTermOutlineBuriedSessionsProxy
- (instancetype)init {
    self = [super init];
    if (self) {
        _children = [[[iTermBuriedSessions sharedInstance] buriedSessions] mapWithBlock:^id(PTYSession *session) {
            return [[iTermOutlineSessionProxy alloc] initWithSession:session];
        }];
    }
    return self;
}

- (BOOL)isExpandable {
    return YES;
}

- (NSString *)displayName {
    return @"Buried Sessions";
}

- (iTermVariableScope *)scope {
    return nil;
}

- (id)identifier {
    return @"";
}

- (void)reveal {
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
    return [NSString stringWithFormat:@"🔲 %@ (%@)", _windowController.window.title, _windowController.terminalGuid];
}

- (iTermVariableScope *)scope {
    return _windowController.scope;
}

- (id)identifier {
    return _windowController.terminalGuid;
}

- (void)reveal {
    [_windowController.currentSession reveal];
}

@end

@interface iTermOutlineRoot : NSObject<iTermOutlineProxy>
@property (nonatomic, readonly) NSArray<id<iTermOutlineProxy>> *children;
@end

@implementation iTermOutlineRoot
- (instancetype)init {
    self = [super init];
    if (self) {
        _children = [[[iTermController sharedInstance] terminals] mapWithBlock:^id(PseudoTerminal *windowController) {
            return [[iTermOutlineWindowProxy alloc] initWithWindowController:windowController];
        }];
        NSArray<PTYSession *> *sessions = [[iTermBuriedSessions sharedInstance] buriedSessions];
        if (sessions.count) {
            _children = [_children arrayByAddingObject:[[iTermOutlineBuriedSessionsProxy alloc] init]];
        }
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

- (id)identifier {
    return [NSNull null];
}

- (void)reveal {
}

@end

@implementation iTermSessionTabWindowOutlineDelegate {
    IBOutlet NSOutlineView *_variablesOutlineView;
    IBOutlet NSOutlineView *_sessionTabWindowOutlineView;
    iTermOutlineRoot *_root;
    iTermVariablesOutlineDelegate *_variablesOutlineDelegate;
    BOOL _picking;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _root = [[iTermOutlineRoot alloc] init];
    }
    return self;
}

- (void)awakeFromNib {
    [_sessionTabWindowOutlineView expandItem:nil expandChildren:YES];
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
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        view.textField = textField;
        [view addSubview:textField];
        [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[textField]-0-|"
                                                                     options:0
                                                                     metrics:nil
                                                                       views:@{ @"textField": textField }]];
        [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[textField]-0-|"
                                                                     options:0
                                                                     metrics:nil
                                                                       views:@{ @"textField": textField }]];
        textField.frame = view.bounds;
        textField.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    }
    view.textField.stringValue = proxy.displayName;
    return view;

}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSOutlineView *outlineView = notification.object;
    id<iTermOutlineProxy> proxy = [outlineView itemAtRow:outlineView.selectedRow];
    [self showVariablesForProxy:proxy];
}

- (void)showVariablesForProxy:(id<iTermOutlineProxy>)proxy {
    iTermVariableScope *scope = proxy.scope;
    if (scope) {
        NSString *path = [_variablesOutlineDelegate selectedPathForOutlineView:_variablesOutlineView];
        _variablesOutlineDelegate = [[iTermVariablesOutlineDelegate alloc] initWithScope:scope];
        _variablesOutlineView.delegate = _variablesOutlineDelegate;
        _variablesOutlineView.dataSource = _variablesOutlineDelegate;
        [_variablesOutlineView reloadData];
        if (path) {
            [_variablesOutlineDelegate selectPath:path inOutlineView:_variablesOutlineView];
        }
    }
}

- (void)selectObjectEquivalentTo:(id<iTermOutlineProxy>)selectedObject {
    const NSInteger numberOfRows = [_sessionTabWindowOutlineView numberOfRows];
    for (NSInteger i = 0; i < numberOfRows; i++) {
        id<iTermOutlineProxy> proxy = [_sessionTabWindowOutlineView itemAtRow:i];
        if ([proxy.identifier isEqual:selectedObject.identifier]) {
            [_sessionTabWindowOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [_sessionTabWindowOutlineView scrollRowToVisible:i];
            return;
        }
    }
    _variablesOutlineDelegate = [[iTermVariablesOutlineDelegate alloc] initWithScope:nil];
    _variablesOutlineView.delegate = _variablesOutlineDelegate;
    _variablesOutlineView.dataSource = _variablesOutlineDelegate;
    [_variablesOutlineView reloadData];
}

- (void)reload {
    id<iTermOutlineProxy> selectedObject = [_sessionTabWindowOutlineView itemAtRow:[_sessionTabWindowOutlineView selectedRow]];
    _root = [[iTermOutlineRoot alloc] init];
    [_sessionTabWindowOutlineView reloadData];
    [_sessionTabWindowOutlineView expandItem:nil expandChildren:YES];
    [self selectObjectEquivalentTo:selectedObject];

}

- (IBAction)reveal:(id)sender {
    id<iTermOutlineProxy> proxy = [_sessionTabWindowOutlineView itemAtRow:_sessionTabWindowOutlineView.clickedRow];
    [proxy reveal];
}

- (IBAction)copyIdentifier:(id)sender {
    id<iTermOutlineProxy> proxy = [_sessionTabWindowOutlineView itemAtRow:_sessionTabWindowOutlineView.clickedRow];
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    [pboard declareTypes:@[NSStringPboardType] owner:NSApp];
    [pboard setString:proxy.identifier forType:NSStringPboardType];
}

- (IBAction)copyPath:(id)sender {
    [_variablesOutlineDelegate copyPath:sender];
}

- (IBAction)copyValue:(id)sender {
    [_variablesOutlineDelegate copyValue:sender];
}

- (IBAction)pickSession:(id)sender {
    if (_picking) {
        return;
    }
    iTermSessionPicker *picker = [[iTermSessionPicker alloc] init];
    PTYSession *session = [picker pickSession];
    if (session) {
        iTermOutlineSessionProxy *proxy = [[iTermOutlineSessionProxy alloc] initWithSession:session];
        [self selectObjectEquivalentTo:proxy];
    }
    NSWindow *window = _sessionTabWindowOutlineView.window;
    // Doesn't work unless you dispatch_async, I guess because modal sessions are a hack.
    dispatch_async(dispatch_get_main_queue(), ^{
        [window makeKeyAndOrderFront:nil];
    });
}

@end
