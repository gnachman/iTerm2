//
//  iTermVariableReference.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/12/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableScope;
@class iTermVariables;

@interface iTermVariableReference<ObjectType> : NSObject

@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) iTermVariableScope *scope;
@property (nullable, nonatomic, copy) void (^onChangeBlock)(void);
@property (nullable, nonatomic, strong) ObjectType value;

- (instancetype)initWithPath:(NSString *)path
                       scope:(iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)removeAllLinks;
- (void)addLinkToVariables:(iTermVariables *)variables
                 localPath:(NSString *)path;
- (void)invalidate;
- (void)valueDidChange;

@end

NS_ASSUME_NONNULL_END
