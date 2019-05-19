//
//  iTermVariables+Private.h
//  iTerm2
//
//  Created by George Nachman on 5/17/19.
//

#import "iTermVariables.h"

@protocol iTermVariableReference;

@interface iTermVariables(Private)

- (NSDictionary<NSString *, NSString *> *)stringValuedDictionaryInScope:(nullable NSString *)scopeName;
- (nullable id)valueForVariableName:(NSString *)name;
- (NSString *)stringValueForVariableName:(NSString *)name;
- (BOOL)hasLinkToReference:(id<iTermVariableReference>)reference
                      path:(NSString *)path;
- (BOOL)setValuesFromDictionary:(NSDictionary<NSString *, id> *)dict;
- (BOOL)setValue:(nullable id)value forVariableNamed:(NSString *)name weak:(BOOL)weak;
- (void)addLinkToReference:(id<iTermVariableReference>)reference
                      path:(NSString *)path;

@end
