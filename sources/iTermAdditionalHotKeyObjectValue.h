//
//  iTermAdditionalHotKeyObjectValue.h
//  iTerm2
//
//  Created by George Nachman on 7/7/16.
//
//

#import <Foundation/Foundation.h>

#import "iTermShortcut.h"
#import "NSDictionary+iTerm.h"

@interface iTermAdditionalHotKeyObjectValue : NSObject

+ (instancetype)objectValueWithShortcut:(iTermShortcut *)shortcut
                       inUseDescriptors:(NSArray<iTermHotKeyDescriptor *> *)descriptors;

@property(nonatomic, retain) iTermShortcut *shortcut;
@property(nonatomic, retain) NSArray<iTermHotKeyDescriptor *> *descriptorsInUseByOtherProfiles;
@property(nonatomic, readonly) BOOL isDuplicate;

@end

