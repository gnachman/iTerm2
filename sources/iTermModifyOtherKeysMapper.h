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

@class VT100Output;
@class iTermModifyOtherKeysMapper;

@protocol iTermModifyOtherKeysMapperDelegate<NSObject>

- (NSStringEncoding)modifiyOtherKeysDelegateEncoding:(iTermModifyOtherKeysMapper *)sender;

- (void)modifyOtherKeys:(iTermModifyOtherKeysMapper *)sender
getOptionKeyBehaviorLeft:(iTermOptionKeyBehavior *)left
                  right:(iTermOptionKeyBehavior *)right;

- (VT100Output *)modifyOtherKeysOutputFactory:(iTermModifyOtherKeysMapper *)sender;

- (BOOL)modifyOtherKeysTerminalIsScreenlike:(iTermModifyOtherKeysMapper *)sender;

@end

@interface iTermModifyOtherKeysMapper : NSObject<iTermKeyMapper>
@property (nonatomic, weak) id<iTermModifyOtherKeysMapperDelegate> delegate;
@end

@interface iTermModifyOtherKeysMapper2: iTermModifyOtherKeysMapper
@end

NS_ASSUME_NONNULL_END
