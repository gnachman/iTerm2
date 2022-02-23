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

// Update keyMapperDictionaryValue when changing this
@interface iTermStandardKeyMapperConfiguration: NSObject
@property (nonatomic, strong) VT100Output *outputFactory;
@property (nonatomic) NSStringEncoding encoding;
@property (nonatomic) iTermOptionKeyBehavior leftOptionKey;
@property (nonatomic) iTermOptionKeyBehavior rightOptionKey;
@property (nonatomic) BOOL screenlike;
@end

NSDictionary *iTermStandardKeyMapperConfigurationDictionaryValue(iTermStandardKeyMapperConfiguration *config);

@protocol iTermStandardKeyMapperDelegate<NSObject>

- (void)standardKeyMapperWillMapKey:(iTermStandardKeyMapper *)standardKeyMapper;

@end

@interface iTermStandardKeyMapper : NSObject<iTermKeyMapper>

@property (nonatomic, weak) id<iTermStandardKeyMapperDelegate> delegate;
@property (nonatomic, strong) iTermStandardKeyMapperConfiguration *configuration;

+ (unichar)codeForSpecialControlCharacter:(unichar)character
               characterIgnoringModifiers:(unichar)characterIgnoringModifiers
                             shiftPressed:(BOOL)shiftPressed;
@end

NS_ASSUME_NONNULL_END
