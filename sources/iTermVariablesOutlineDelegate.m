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

@interface iTermVariablesTerminalProxy : NSObject<iTermVariablesProxy>
- (instancetype)initWithName:(NSString *)name value:(id)value;
@end

@interface iTermVariablesWeakNonterminalProxy : NSObject<iTermVariablesProxy>
- (instancetype)initWithName:(NSString *)name variables:(iTermVariables *)variables;
@end

@interface iTermVariablesNonterminalProxy : NSObject<iTermVariablesProxy>
- (instancetype)initWithName:(NSString *)name variables:(iTermVariables *)variables;
@end

@interface iTermVariablesScopeProxy : NSObject<iTermVariablesProxy>
@property (nonatomic, readonly) iTermVariableScope *scope;
@property (nonatomic, readonly) NSArray<iTermVariablesNonterminalProxy *> *children;
- (instancetype)initWithScope:(iTermVariableScope *)scope;
@end

id iTermVariablesNewProxy(NSString *name, id value) {
    iTermVariables *nested = [iTermVariables castFrom:value];
    if (nested) {
        return [[iTermVariablesNonterminalProxy alloc] initWithName:name variables:nested];
    }
    iTermWeakVariables *weak = [iTermWeakVariables castFrom:value];
    if (weak) {
        if (!weak.variables) {
            return nil;
        }
        return [[iTermVariablesWeakNonterminalProxy alloc] initWithName:name variables:weak.variables];
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
}

@synthesize children = _children;

- (instancetype)initWithName:(NSString *)name variables:(iTermVariables *)variables {
    self = [super init];
    if (self) {
        _name = [name copy];
        _variables = variables;
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
        return iTermVariablesNewProxy(name, value);
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
    return @"⭫ Parent Object";
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
            return iTermVariablesNewProxy(name, value);
        }];
    }
    return self;
}

- (NSString *)path {
    return _name;
}

- (NSString *)value {
    if (_children.count == 1) {
        return @"1 child";
    }
    return [NSString stringWithFormat:@"%@ children", @(_children.count)];
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
                    return iTermVariablesNewProxy(name, value);
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
