//
//  iTermAdditionalHotKeyObjectValue.m
//  iTerm2
//
//  Created by George Nachman on 7/7/16.
//
//

#import "iTermAdditionalHotKeyObjectValue.h"

@implementation iTermAdditionalHotKeyObjectValue

+ (instancetype)objectValueWithShortcut:(iTermShortcut *)shortcut
                       inUseDescriptors:(NSArray<iTermHotKeyDescriptor *> *)descriptors {
    iTermAdditionalHotKeyObjectValue *objectValue = [[[iTermAdditionalHotKeyObjectValue alloc] init] autorelease];
    objectValue.shortcut = shortcut;
    objectValue.descriptorsInUseByOtherProfiles = descriptors;
    return objectValue;
}

- (void)dealloc {
    [_shortcut release];
    [_descriptorsInUseByOtherProfiles release];
    [super dealloc];
}

- (BOOL)isDuplicate {
    return [_descriptorsInUseByOtherProfiles containsObject:_shortcut.descriptor];
}

@end
