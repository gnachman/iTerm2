//
//  iTermFunctionCallSuggester.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/18.
//

#import <Foundation/Foundation.h>

@interface iTermFunctionCallSuggester : NSObject

- (instancetype)initWithFunctionSignatures:(NSDictionary<NSString *, NSArray<NSString *> *> *)functionSignatures
                                     paths:(NSArray<NSString *> *)paths NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<NSString *> *)suggestionsForString:(NSString *)prefix;

@end
