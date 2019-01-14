//
//  iTermVariablesOutlineDelegate.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import "iTermVariablesOutlineDelegate.h"
#import "iTermVariableScope.h"
#import "iTermWeakVariables.h"
#import "NSArray+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"

@protocol iTermVariablesProxy<NSObject>
@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSString *value;
@property (nonatomic, readonly) NSArray<id<iTermVariablesProxy>> *children;
@property (nonatomic, readonly) BOOL isExpandable;
@end

@interface iTermVariablesOutlineMenu : NSMenu
@property (nonatomic, strong) IBOutlet NSOutlineView *outlineView;
@end

@implementation iTermVariablesOutlineMenu
@end

@interface iTermVariablesTerminalProxy : NSObject<iTermVariablesProxy>
- (instancetype)initWithName:(NSString *)name value:(id)value;
@end

@interface iTermVariablesWeakNonterminalProxy : NSObject<iTermVariablesProxy>
- (instancetype)initWithName:(NSString *)name variables:(iTermVariables *)variables isAlias:(BOOL)isAlias;
@end

@interface iTermVariablesNonterminalProxy : NSObject<iTermVariablesProxy>
- (instancetype)initWithName:(NSString *)name variables:(iTermVariables *)variables;
@end

@interface iTermVariablesScopeProxy : NSObject<iTermVariablesProxy>
@property (nonatomic, readonly) iTermVariableScope *scope;
@property (nonatomic, readonly) NSArray<iTermVariablesNonterminalProxy *> *children;
- (instancetype)initWithScope:(iTermVariableScope *)scope;
@end

id iTermVariablesNewProxy(NSString *name, id value, BOOL isAlias) {
    iTermVariables *nested = [iTermVariables castFrom:value];
    if (nested) {
        return [[iTermVariablesNonterminalProxy alloc] initWithName:name variables:nested];
    }
    iTermWeakVariables *weak = [iTermWeakVariables castFrom:value];
    if (weak) {
        if (!weak.variables) {
            return nil;
        }
        return [[iTermVariablesWeakNonterminalProxy alloc] initWithName:name variables:weak.variables isAlias:isAlias];
    }

    return [[iTermVariablesTerminalProxy alloc] initWithName:name value:value];
}

@implementation iTermVariablesTerminalProxy {
    NSString *_name;
    id _value;
}

- (instancetype)initWithName:(NSString *)name value:(id)value {
    self = [super init];
    if (self) {
        _name = name;
        _value = value;
    }
    return self;
}

- (BOOL)isExpandable {
    return NO;
}

- (NSString *)path {
    return _name;
}

- (NSString *)value {
    if ([_value isKindOfClass:[NSString class]]) {
        return _value;
    }
    return [NSJSONSerialization it_jsonStringForObject:_value];
}

- (NSArray<id<iTermVariablesProxy>> *)children {
    return @[];
}

@end

@implementation iTermVariablesWeakNonterminalProxy {
    NSString *_name;
    iTermVariables *_variables;
    BOOL _isAlias;
}

@synthesize children = _children;

- (instancetype)initWithName:(NSString *)name variables:(iTermVariables *)variables isAlias:(BOOL)isAlias {
    self = [super init];
    if (self) {
        _name = [name copy];
        _variables = variables;
        _isAlias = isAlias;
    }
    return self;
}

// Compute children lazily to avoid an infinite loop
- (NSArray<id<iTermVariablesProxy>> *)children {
    if (_children) {
        return _children;
    }
    _children = [_variables.allNames mapWithBlock:^id(NSString *name) {
        id value = [self->_variables rawValueForVariableName:name];
        const BOOL isAlias = [[iTermWeakVariables castFrom:value] variables] == self->_variables;
        return iTermVariablesNewProxy(name, value, isAlias);
    }];
    return _children;
}

- (BOOL)isExpandable {
    return YES;
}

- (NSString *)path {
    return _name;
}

- (NSString *)value {
    return _isAlias ? @"↶ Alias" : @"⭫ Parent Object";
}

@end

@implementation iTermVariablesNonterminalProxy {
    NSString *_name;
    iTermVariables *_variables;
}

@synthesize children = _children;

- (instancetype)initWithName:(NSString *)name variables:(iTermVariables *)variables {
    assert(name);
    self = [super init];
    if (self) {
        _name = [name copy];
        _variables = variables;
        _children = [variables.allNames mapWithBlock:^id(NSString *name) {
            id value = [variables rawValueForVariableName:name];
            return iTermVariablesNewProxy(name, value, NO);
        }];
    }
    return self;
}

- (NSString *)path {
    return _name;
}

- (NSString *)value {
    return @"";
}

- (BOOL)isExpandable {
    return YES;
}

@end

@implementation iTermVariablesScopeProxy

- (instancetype)initWithScope:(iTermVariableScope *)scope {
    self = [super init];
    if (self) {
        _scope = scope;
        _children = [scope.frames flatMapWithBlock:^id(iTermTuple<NSString *,iTermVariables *> *tuple) {
            if (tuple.firstObject) {
                return @[ [[iTermVariablesNonterminalProxy alloc] initWithName:tuple.firstObject
                                                                     variables:tuple.secondObject] ];
            } else {
                return [tuple.secondObject.allNames mapWithBlock:^id(NSString *name) {
                    id value = [tuple.secondObject rawValueForVariableName:name];
                    iTermWeakVariables *weakVariables = [iTermWeakVariables castFrom:value];
                    const BOOL isAlias = (tuple.firstObject == nil &&
                                          tuple.secondObject == weakVariables.variables);
                    return iTermVariablesNewProxy(name, value, isAlias);
                }];
            }
        }] ?: @[];
    }
    return self;
}

- (NSString *)path {
    return @"Scope";
}

- (NSString *)value {
    return @"";
}

- (BOOL)isExpandable {
    return YES;
}
@end

@implementation iTermVariablesOutlineDelegate {
    iTermVariablesScopeProxy *_root;
}

- (instancetype)initWithScope:(iTermVariableScope *)scope {
    self = [super init];
    if (self) {
        _root = [[iTermVariablesScopeProxy alloc] initWithScope:scope];
    }
    return self;
}

- (NSString *)selectedPathForOutlineView:(NSOutlineView *)outlineView {
    return [self pathForRow:outlineView.selectedRow
                outlineView:outlineView];
}

- (NSString *)pathForRow:(NSInteger)row outlineView:(NSOutlineView *)outlineView {
    if (row < 0) {
        return nil;
    }
    NSArray<NSString *> *parts = @[];
    id<iTermVariablesProxy> proxy = [outlineView itemAtRow:row];
    while (proxy && proxy != _root) {
        parts = [@[proxy.path] arrayByAddingObjectsFromArray:parts];
        proxy = [outlineView parentForItem:proxy];
    }
    return [parts componentsJoinedByString:@"."];
}

- (void)selectPath:(NSString *)path inOutlineView:(NSOutlineView *)outlineView {
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"."];
    id<iTermVariablesProxy> proxy = _root;
    while (parts.count) {
        NSString *name = parts.firstObject;
        BOOL found = NO;
        for (id<iTermVariablesProxy> child in proxy.children) {
            if ([child.path isEqualToString:name]) {
                found = YES;
                [outlineView expandItem:proxy];
                proxy = child;
                parts = [parts subarrayFromIndex:1];
                break;
            }
        }
        if (!found) {
            return;
        }
    }
    const NSInteger row = [outlineView rowForItem:proxy];
    if (row < 0) {
        return;
    }
    [outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [outlineView scrollRowToVisible:row];
}

- (void)copyPath:(id)sender {
    NSOutlineView *outlineView = [[iTermVariablesOutlineMenu castFrom:[sender menu]] outlineView];
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    [pboard declareTypes:@[NSStringPboardType] owner:NSApp];
    [pboard setString:[self pathForRow:outlineView.clickedRow outlineView:outlineView]
              forType:NSStringPboardType];
}

- (void)copyValue:(id)sender {
    NSOutlineView *outlineView = [[iTermVariablesOutlineMenu castFrom:[sender menu]] outlineView];
    id<iTermVariablesProxy> proxy = [outlineView itemAtRow:outlineView.clickedRow];
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    [pboard declareTypes:@[NSStringPboardType] owner:NSApp];
    [pboard setString:proxy.value
              forType:NSStringPboardType];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
    id<iTermVariablesProxy> proxy = item ?: _root;
    return proxy.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
    id<iTermVariablesProxy> proxy = item ?: _root;
    return proxy.children[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    id<iTermVariablesProxy> proxy = item ?: _root;
    return proxy.isExpandable;
}

#pragma mark - NSOutlineViewDelegate

// View Based OutlineView: See the delegate method -tableView:viewForTableColumn:row: in NSTableView.
- (nullable NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(nullable NSTableColumn *)tableColumn item:(id)item {
    id<iTermVariablesProxy> proxy = item;
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

    if ([tableColumn.identifier isEqualToString:@"path"]) {
        view.textField.stringValue = proxy.path;
    } else {
        view.textField.stringValue = proxy.value;
    }
    return view;

}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
}

@end
