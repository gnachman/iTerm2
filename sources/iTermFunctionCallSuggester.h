//
//  iTermFunctionCallSuggester.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermFunctionCallSuggester<NSObject>
- (NSArray<NSString *> *)suggestionsForString:(NSString *)prefix;
@end


@interface iTermFunctionCallSuggester : NSObject<iTermFunctionCallSuggester>

- (instancetype)initWithFunctionSignatures:(NSDictionary<NSString *, NSArray<NSString *> *> *)functionSignatures
                                pathSource:(NSSet<NSString *> *(^)(NSString *prefix))pathSource NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

// Expects a string like "foo" or "foo\(bar())", including nested madness like foo\(bar(\"baz()")).
// Of course, any such string may be truncated and appropriate suggestions will result.
@interface iTermSwiftyStringSuggester : iTermFunctionCallSuggester
@end

@interface iTermExpressionSuggester: iTermFunctionCallSuggester
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END

