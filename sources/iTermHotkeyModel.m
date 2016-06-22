//
//  iTermHotkeyModel.m
//  iTerm2
//
//  Created by George Nachman on 6/21/16.
//
//

#import "iTermHotkeyModel.h"

NSString *const kKeyCombination = @"keyCombination";
NSString *const kAutoHide = @"autoHide";
NSString *const kShowAfterAutoHiding = @"showAfterAutoHiding";
NSString *const kRevealOnDockClick = @"revealOnDockClick";
NSString *const kRevealOnDockClickOnlyIfNoOpenWindowsExist = @"revealOnDockClickOnlyIfNoOpenWindowsExist";
NSString *const kAnimate = @"animate";

@implementation iTermHotKeyModel

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        _keyCombination = dictionary[kKeyCombination];
        _autoHide = [dictionary[kAutoHide] boolValue];
        _showAfterAutoHiding = [dictionary[kShowAfterAutoHiding] boolValue];
        _revealOnDockClick = [dictionary[kRevealOnDockClick] boolValue];
        _revealOnDockClickOnlyIfNoOpenWindowsExist = [dictionary[kRevealOnDockClickOnlyIfNoOpenWindowsExist] boolValue];
        id value = dictionary[kAnimate] ?: @YES;
        _animate = [value boolValue];
    }
    return self;
}

- (void)dealloc {
    [_keyCombination release];
    [super dealloc];
}

- (NSDictionary *)dictionaryValue {
    return @{ kKeyCombination: _keyCombination ?: @"",
              kAutoHide: @(_autoHide),
              kShowAfterAutoHiding: @(_showAfterAutoHiding),
              kRevealOnDockClick: @(_revealOnDockClick),
              kRevealOnDockClickOnlyIfNoOpenWindowsExist: @(_revealOnDockClickOnlyIfNoOpenWindowsExist),
              kAnimate: @(_animate) };
}

@end
