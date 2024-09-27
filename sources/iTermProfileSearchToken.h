//
//  iTermProfileSearchToken.h
//  iTerm2
//
//  Created by George Nachman on 5/14/15.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kTagRestrictionOperator;

@interface iTermProfileSearchToken : NSObject

@property(nonatomic, readonly) NSRange range;
@property(nonatomic, readonly) BOOL negated;
@property(nonatomic, readonly) BOOL isTag;
// The actual operator for this token, if any.
@property(nonatomic, readonly, copy, nullable) NSString *operator;

/// operators gives the list of defined operators.
- (instancetype)initWithPhrase:(NSString *)phrase operators:(NSArray<NSString *> *)operators;
- (instancetype)initWithTag:(NSString *)tag operators:(NSArray<NSString *> *)operators;

- (instancetype)initWithPhrase:(NSString *)phrase;
- (instancetype)initWithTag:(NSString *)tag;

// This assumes the operator is not tag:
- (BOOL)matchesAnyWordIn:(NSArray<NSString * > *)words operator:(NSString *)operator;

- (BOOL)matchesAnyWordInNameWords:(NSArray<NSString * > * _Nullable)nameWords;
- (BOOL)matchesAnyWordInTagWords:(NSArray<NSString * > *)tagWords;

@end

NS_ASSUME_NONNULL_END
