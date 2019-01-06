//
//  iTermTermkeyKeyMapper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/30/18.
//

#import <Cocoa/Cocoa.h>

#import "ITAddressBookMgr.h"
#import "iTermKeyMapper.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermTermkeyKeyMapper;

typedef struct {
    NSStringEncoding encoding;
    iTermOptionKeyBehavior leftOptionKey;
    iTermOptionKeyBehavior rightOptionKey;
    BOOL applicationCursorMode;
    BOOL applicationKeypadMode;
} iTermTermkeyKeyMapperConfiguration;

@protocol iTermTermkeyKeyMapperDelegate<NSObject>
- (void)termkeyKeyMapperWillMapKey:(iTermTermkeyKeyMapper *)termkeyKeyMaper;
@end

@interface iTermTermkeyKeyMapper : NSObject<iTermKeyMapper>

@property (nonatomic, weak) id<iTermTermkeyKeyMapperDelegate> delegate;
@property (nonatomic) iTermTermkeyKeyMapperConfiguration configuration;

@end

NS_ASSUME_NONNULL_END
