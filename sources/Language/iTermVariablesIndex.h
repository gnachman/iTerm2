//
//  iTermVariablesIndex.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/17/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermVariables;

@interface iTermVariablesIndex : NSObject

+ (instancetype)sharedInstance;

- (void)removeKey:(NSString *)key;
- (void)setVariables:(iTermVariables *)variables forKey:(NSString *)key;
- (nullable iTermVariables *)variablesForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
