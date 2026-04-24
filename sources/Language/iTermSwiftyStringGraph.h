//
//  iTermSwiftyStringGraph.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 23/02/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermSwiftyString;
@class iTermVariableScope;

@interface iTermSwiftyStringGraph : NSObject
@property (nonatomic, readonly) iTermVariableScope *scope;

- (void)addSwiftyString:(iTermSwiftyString *)swiftyString
         withFormatPath:(nullable NSString *)formatPath
         evaluationPath:(NSString *)evaluationPath
                  scope:(iTermVariableScope *)scope;

- (void)addEdgeFromPath:(NSString *)fromPath
                 toPath:(NSString *)toPath
                  scope:(iTermVariableScope *)scope;

- (BOOL)containsCycle;
@end

NS_ASSUME_NONNULL_END
