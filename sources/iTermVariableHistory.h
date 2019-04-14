//
//  iTermVariableHistory.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, iTermVariablesSuggestionContext) {
    iTermVariablesSuggestionContextNone = 0,
    iTermVariablesSuggestionContextSession = (1 << 0),
    iTermVariablesSuggestionContextTab = (1 << 1),
    iTermVariablesSuggestionContextApp = (1 << 2),
    // NOTE: 1<<3 is missing!
    iTermVariablesSuggestionContextWindow = (1 << 4),
};

@interface iTermVariableHistory : NSObject

+ (NSString *)stringForContext:(iTermVariablesSuggestionContext)context;
+ (void)recordBuiltInVariables;
+ (void)recordUseOfVariableNamed:(NSString *)name
                       inContext:(iTermVariablesSuggestionContext)context;
+ (NSSet<NSString *> *(^)(NSString *))pathSourceForContext:(iTermVariablesSuggestionContext)context;
+ (NSSet<NSString *> *(^)(NSString *))pathSourceForContext:(iTermVariablesSuggestionContext)context
                                             augmentedWith:(NSSet<NSString *> *)augmentations;
+ (NSSet<NSString *> *(^)(NSString *))pathSourceForContext:(iTermVariablesSuggestionContext)context
                                                 excluding:(NSSet<NSString *> *)exclusions
                                             allowUserVars:(BOOL)allowUserVars;


@end

NS_ASSUME_NONNULL_END
