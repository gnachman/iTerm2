//
//  iTermInitialDirectory.h
//  iTerm2
//
//  Created by George Nachman on 8/14/16.
//
//

#import <Foundation/Foundation.h>

#import "ProfileModel.h"
#import "ITAddressBookMgr.h"

@class iTermVariableScope;

typedef NS_ENUM(NSUInteger, iTermInitialDirectoryMode) {
    iTermInitialDirectoryModeHome,
    iTermInitialDirectoryModeRecycle,
    iTermInitialDirectoryModeCustom
};

@interface iTermInitialDirectory : NSObject
@property(nonatomic, assign) iTermInitialDirectoryMode mode;

// Only used if mode is Custom. Is a swifty string.
@property(nonatomic, copy) NSString *customDirectoryFormat;

+ (instancetype)initialDirectoryFromProfile:(Profile *)profile
                                 objectType:(iTermObjectType)objectType;

- (void)evaluateWithOldPWD:(NSString *)oldPWD
                     scope:(iTermVariableScope *)scope
                completion:(void (^)(NSString *))completion;

@end

