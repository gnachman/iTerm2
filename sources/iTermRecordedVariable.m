//
//  iTermRecordedVariable.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import "iTermRecordedVariable.h"

#import "iTermVariableHistory.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermRecordedVariable

- (instancetype)recordByPrependingPath:(NSString *)path {
    NSString *name = [path stringByAppendingString:_name];
    if (self.isTerminal) {
        return [[iTermRecordedVariable alloc] initTerminalWithName:name];
    } else {
        return [[iTermRecordedVariable alloc] initNonterminalWithName:name context:_nonterminalContext];
    }
}

- (instancetype)initTerminalWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _name = [name copy];
        _isTerminal = YES;
    }
    return self;
}

- (instancetype)initNonterminalWithName:(NSString *)name context:(iTermVariablesSuggestionContext)context {
    self = [super init];
    if (self) {
        _name = [name copy];
        _nonterminalContext = context;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    BOOL isTerminal = [dict[@"isTerminal"] boolValue];
    if (isTerminal) {
        return [self initTerminalWithName:dict[@"name"]];
    } else {
        return [self initNonterminalWithName:dict[@"name"]
                                     context:[dict[@"nonterminalContext"] unsignedIntegerValue]];
    }
}

- (NSString *)description {
    if (_isTerminal) {
        return [NSString stringWithFormat:@"<%@: %p name=%@ terminal>", NSStringFromClass(self.class), self, self.name];
    } else {
        NSString *context = [iTermVariableHistory stringForContext:_nonterminalContext];
        return [NSString stringWithFormat:@"<%@: %p name=%@ nonterminal %@>", NSStringFromClass(self.class), self, self.name, context];
    }
}

- (NSUInteger)hash {
    return [_name hash];
}

- (BOOL)isEqual:(id)object {
    iTermRecordedVariable *other = [iTermRecordedVariable castFrom:object];
    if (!other) {
        return NO;
    }
    return ([NSObject object:_name isEqualToObject:other->_name] &&
            _isTerminal == other->_isTerminal &&
            _nonterminalContext == other->_nonterminalContext);
}

- (NSDictionary *)dictionaryValue {
    return @{ @"name": _name,
              @"isTerminal": @(_isTerminal),
              @"nonterminalContext": @(_nonterminalContext) };
}

@end

NS_ASSUME_NONNULL_END
