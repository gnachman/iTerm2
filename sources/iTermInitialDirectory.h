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

typedef NS_ENUM(NSUInteger, iTermInitialDirectoryMode) {
    iTermInitialDirectoryModeHome,
    iTermInitialDirectoryModeRecycle,
    iTermInitialDirectoryModeCustom
};

@interface iTermInitialDirectory : NSObject
@property(nonatomic, assign) iTermInitialDirectoryMode mode;

// Only used if mode is Custom
@property(nonatomic, copy) NSString *customDirectory;

+ (instancetype)initialDirectoryFromProfile:(Profile *)profile
                                 objectType:(iTermObjectType)objectType;

@end

