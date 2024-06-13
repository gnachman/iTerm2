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

- (instancetype)initWithPhrase:(NSString *)phrase operators:(NSArray<NSString *> *)operators;
- (instancetype)initWithTag:(NSString *)tag operators:(NSArray<NSString *> *)operators;

- (instancetype)initWithPhrase:(NSString *)phrase;
- (instancetype)initWithTag:(NSString *)tag;

// This assumes the operator is not tag:
- (BOOL)matchesAnyWordIn:(NSArray<NSString * > *)words operator:(NSString *)operator;

- (BOOL)matchesAnyWordInNameWords:(NSArray<NSString * > *)nameWords;
- (BOOL)matchesAnyWordInTagWords:(NSArray<NSString * > *)tagWords;

@end

NS_ASSUME_NONNULL_END
