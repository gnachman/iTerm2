//
//  iTermModifyOtherKeysMapper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/12/20.
//

#import <Foundation/Foundation.h>
#import "ITAddressBookMgr.h"
#import "iTermKeyMapper.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermModifyOtherKeysMapper;

@protocol iTermModifyOtherKeysMapperDelegate<NSObject>

- (NSStringEncoding)modifiyOtherKeysDelegateEncoding:(iTermModifyOtherKeysMapper *)sender;

- (void)modifyOtherKeys:(iTermModifyOtherKeysMapper *)sender
getOptionKeyBehaviorLeft:(iTermOptionKeyBehavior *)left
                  right:(iTermOptionKeyBehavior *)right;

@end

@interface iTermModifyOtherKeysMapper : NSObject<iTermKeyMapper>
@property (nonatomic, weak) id<iTermModifyOtherKeysMapperDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
