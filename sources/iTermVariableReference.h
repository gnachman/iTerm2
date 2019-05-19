//
//  iTermVariableReference.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/12/18.
//

#import <Foundation/Foundation.h>
#import "iTermVariables.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableScope;

@interface iTermVariableReference<ObjectType> : NSObject<iTermVariableReference>

@property (nonatomic, readonly) id<iTermVariableVendor> vendor;
@property (nullable, nonatomic, strong) ObjectType value;

- (instancetype)initWithPath:(NSString *)path
                      vendor:(id<iTermVariableVendor>)vendor NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
