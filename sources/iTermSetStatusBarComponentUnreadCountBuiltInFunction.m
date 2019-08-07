//
//  iTermSetStatusBarComponentUnreadCountBuiltInFunction.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/6/19.
//

#import "iTermSetStatusBarComponentUnreadCountBuiltInFunction.h"

#import "iTermStatusBarUnreadCountController.h"

@implementation iTermSetStatusBarComponentUnreadCountBuiltInFunction

+ (void)registerBuiltInFunction {
    static NSString *const identifier = @"identifier";
    static NSString *const count = @"count";

    iTermBuiltInFunction *func =
    [[iTermBuiltInFunction alloc] initWithName:@"set_status_bar_component_unread_count"
                                     arguments:@{ identifier: [NSString class],
                                                  count: [NSNumber class] }
                             optionalArguments:[NSSet set]
                                 defaultValues:@{ }
                                       context:iTermVariablesSuggestionContextNone
                                         block:
     ^(NSDictionary * _Nonnull parameters, iTermBuiltInFunctionCompletionBlock  _Nonnull completion) {
         [self setCount:[parameters[count] integerValue] forIdentifier:parameters[identifier] completion:completion];
     }];
    [[iTermBuiltInFunctions sharedInstance] registerFunction:func
                                                   namespace:@"iterm2"];
}

+ (void)setCount:(NSInteger)count forIdentifier:(NSString *)identifier completion:(iTermBuiltInFunctionCompletionBlock)completion {
    [[iTermStatusBarUnreadCountController sharedInstance] setUnreadCountForComponentWithIdentifier:identifier
                                                                                             count:count];
    completion(nil, nil);
}

@end
