//
//  iTermHapticActuator.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/6/19.
//
// Derived from https://raw.githubusercontent.com/niw/HapticKey/master/HapticKey/Classes/HTKMultitouchActuator.m
//  Copyright © 2017 Yoshimasa Niwa. All rights reserved.

#import "iTermHapticActuator.h"
#import "DebugLogging.h"
#import "FutureMethods.h"

@import IOKit;

NS_ASSUME_NONNULL_BEGIN

@interface iTermHapticActuator ()

@property (nonatomic) UInt64 lastKnownMultitouchDeviceMultitouchID;

@end

@implementation iTermHapticActuator {
    CFTypeRef _actuatorRef;
    MTActuatorCreateFromDeviceIDFunction *_MTActuatorCreateFromDeviceID;
    MTActuatorOpenFunction *_MTActuatorOpen;
    MTActuatorCloseFunction *_MTActuatorClose;
    MTActuatorActuateFunction *_MTActuatorActuate;
    MTActuatorIsOpenFunction *_MTActuatorIsOpen;
}

+ (instancetype)sharedActuator {
    static dispatch_once_t onceToken;
    static iTermHapticActuator *sharedActuator;
    dispatch_once(&onceToken, ^{
        sharedActuator = [[iTermHapticActuator alloc] init];
    });
    return sharedActuator;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _feedbackType = iTermHapticFeedbackTypeStrong;
        
        _MTActuatorCreateFromDeviceID = iTermGetMTActuatorCreateFromDeviceIDFunction();
        _MTActuatorOpen = iTermGetMTActuatorOpenFunction();
        _MTActuatorClose = iTermGetMTActuatorCloseFunction();
        _MTActuatorActuate = iTermGetMTActuatorActuateFunction();
        _MTActuatorIsOpen = iTermGetMTActuatorIsOpenFunction();
        
        if (!_MTActuatorCreateFromDeviceID ||
            !_MTActuatorOpen ||
            !_MTActuatorClose ||
            !_MTActuatorActuate ||
            !_MTActuatorIsOpen) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    [self _htk_main_closeActuator];
}

- (void)actuateTouchDownFeedback {
    [self actuateActuationID:[self actuationIDForType:_feedbackType]
                    unknown1:0
                    unknown2:0.0
                    unknown3:2.0];
}

- (void)actuateTouchUpFeedback {
    [self actuateActuationID:[self actuationIDForType:_feedbackType]
                    unknown1:0
                    unknown2:0.0
                    unknown3:0.0];
}

- (BOOL)actuateActuationID:(SInt32)actuationID
                  unknown1:(UInt32)unknown1
                  unknown2:(Float32)unknown2
                  unknown3:(Float32)unknown3 {
    [self _htk_main_openActuator];
    BOOL result = [self _htk_main_actuateActuationID:actuationID unknown1:unknown1 unknown2:unknown2 unknown3:unknown3];
    
    // In case we failed to actuate with existing actuator, reopen it and try again.
    if (!result) {
        [self _htk_main_closeActuator];
        [self _htk_main_openActuator];
        result = [self _htk_main_actuateActuationID:actuationID unknown1:unknown1 unknown2:unknown2 unknown3:unknown3];
    }
    
    return result;
}

// By using IORegistryExplorer, which is in Additional Tools for Xcode,
// Find `AppleMultitouchDevice` which has `Multitouch ID`.
// Probably these are fixed value.
static const UInt64 kKnownAppleMultitouchDeviceMultitouchIDs[] = {
    // For MacBook Pro 2016, 2017
    0x200000001000000,
    // For MacBook Pro 2018
    0x300000080500000
};

- (void)_htk_main_openActuator {
    if (_actuatorRef) {
        return;
    }
    
    if (self.lastKnownMultitouchDeviceMultitouchID) {
        const CFTypeRef actuatorRef = _MTActuatorCreateFromDeviceID(self.lastKnownMultitouchDeviceMultitouchID);
        if (!actuatorRef) {
            DLog(@"Fail to MTActuatorCreateFromDeviceID: 0x%llx", self.lastKnownMultitouchDeviceMultitouchID);
            return;
        }
        _actuatorRef = actuatorRef;
    } else {
        const size_t count = sizeof(kKnownAppleMultitouchDeviceMultitouchIDs) / sizeof(UInt64);
        for (size_t index = 0; index < count; index++) {
            const UInt64 multitouchDeviceMultitouchID = kKnownAppleMultitouchDeviceMultitouchIDs[index];
            const CFTypeRef actuatorRef = _MTActuatorCreateFromDeviceID(multitouchDeviceMultitouchID);
            if (actuatorRef) {
                DLog(@"Use MTActuatorCreateFromDeviceID: 0x%llx", multitouchDeviceMultitouchID);
                _actuatorRef = actuatorRef;
                self.lastKnownMultitouchDeviceMultitouchID = multitouchDeviceMultitouchID;
                break;
            }
            DLog(@"Fail to test MTActuatorCreateFromDeviceID: 0x%llx", multitouchDeviceMultitouchID);
        }
        if (!_actuatorRef) {
            DLog(@"Fail to MTActuatorCreateFromDeviceID");
            return;
        }
    }
    
    const IOReturn error = _MTActuatorOpen(_actuatorRef);
    if (error != kIOReturnSuccess) {
        DLog(@"Fail to MTActuatorOpen: %p error: 0x%x", _actuatorRef, error);
        CFRelease(_actuatorRef);
        _actuatorRef = NULL;
        return;
    }
}

- (void)_htk_main_closeActuator {
    if (!_actuatorRef) {
        return;
    }
    
    const IOReturn error = _MTActuatorClose(_actuatorRef);
    if (error != kIOReturnSuccess) {
        DLog(@"Fail to MTActuatorClose: %p error: 0x%x", _actuatorRef, error);
    }
    CFRelease(_actuatorRef);
    _actuatorRef = NULL;
}

- (BOOL)_htk_main_actuateActuationID:(SInt32)actuationID unknown1:(UInt32)unknown1 unknown2:(Float32)unknown2 unknown3:(Float32)unknown3 {
    if (!_actuatorRef) {
        DLog(@"The actuator is not opend yet.");
        return NO;
    }
    
    const IOReturn error = _MTActuatorActuate(_actuatorRef, actuationID, unknown1, unknown2, unknown3);
    if (error != kIOReturnSuccess) {
        DLog(@"Fail to MTActuatorActuate: %p, %d, %d, %f, %f error: 0x%x", _actuatorRef, actuationID, unknown1, unknown2, unknown3, error);
        return NO;
    } else {
        return YES;
    }
}

- (SInt32)actuationIDForType:(iTermHapticFeedbackType)type {
    // To find predefiend actuation ID, run next command.
    // $ otool -s __TEXT __tpad_act_plist /System/Library/PrivateFrameworks/MultitouchSupport.framework/Versions/Current/MultitouchSupport|tail -n +3|awk -F'\t' '{print $2}'|xxd -r -p
    // This show a embeded property list file in `MultitouchSupport.framework`.
    // There are default 1, 2, 3, 4, 5, 6, 15, and 16 actuation IDs now.
    
    switch (type) {
        case iTermHapticFeedbackTypeNone:
            return 0;
        case iTermHapticFeedbackTypeWeak:
            return 3;
        case iTermHapticFeedbackTypeMedium:
            return 4;
        case iTermHapticFeedbackTypeStrong:
            return 6;
    }
    return 0;
}

@end

NS_ASSUME_NONNULL_END
