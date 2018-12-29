//
//  iTermStandardKeyMapper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/29/18.
//

#import <Cocoa/Cocoa.h>

#import "ITAddressBookMgr.h"
#import "iTermKeyMapper.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermStandardKeyMapper;
@class VT100Output;

typedef struct {
    VT100Output *outputFactory;
    NSStringEncoding encoding;
    iTermOptionKeyBehavior leftOptionKey;
    iTermOptionKeyBehavior rightOptionKey;
    BOOL screenlike;
} iTermStandardKeyMapperConfiguration;

@protocol iTermStandardKeyMapperDelegate<NSObject>

- (void)standardKeyMapperWillMapKey:(iTermStandardKeyMapper *)standardKeyMapper;

@end

@interface iTermStandardKeyMapper : NSObject<iTermKeyMapper>

@property (nonatomic, weak) id<iTermStandardKeyMapperDelegate> delegate;
@property (nonatomic) iTermStandardKeyMapperConfiguration configuration;

@end

NS_ASSUME_NONNULL_END
