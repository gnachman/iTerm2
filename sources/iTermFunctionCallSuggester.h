//
//  iTermFunctionCallSuggester.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>

@interface iTermFunctionCallSuggester : NSObject

- (instancetype)initWithFunctionSignatures:(NSDictionary<NSString *, NSArray<NSString *> *> *)functionSignatures
                                     paths:(NSSet<NSString *> *)paths NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<NSString *> *)suggestionsForString:(NSString *)prefix;

@end

// Expects a string like "foo" or "foo\(bar())", including nested madness like foo\(bar(\"baz()")).
// Of course, any such string may be truncated and appropriate suggestions will result.
@interface iTermSwiftyStringSuggester : iTermFunctionCallSuggester
@end
