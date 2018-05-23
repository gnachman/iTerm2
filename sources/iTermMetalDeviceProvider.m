//
//  iTermMetalDeviceProvider.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/18.
//
#if ENABLE_LOW_POWER_GPU_DETECTION
#import "iTermMetalDeviceProvider.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermPowerManager.h"
#import "NSArray+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const iTermMetalDeviceProviderPreferredDeviceDidChangeNotification = @"iTermMetalDeviceProviderPreferredDeviceDidChangeNotification";

@implementation iTermMetalDeviceProvider {
    NSArray<id<MTLDevice>> *_deviceList;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _deviceList = MTLCopyAllDevices();
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(powerManagerStateDidChange:)
                                                     name:iTermPowerManagerStateDidChange
                                                   object:nil];
        _preferredDevice = [self findPreferredDevice];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (nullable id<MTLDevice>)integratedGPU {
    return [_deviceList objectPassingTest:^BOOL(id<MTLDevice> element, NSUInteger index, BOOL *stop) {
        if (@available(macOS 10.13, *)) {
            if (element.removable) {
                return NO;
            }
        }
        return element.lowPower && !element.headless;
    }];
}

- (nullable id<MTLDevice>)discreteGPU {
    return [_deviceList objectPassingTest:^BOOL(id<MTLDevice> element, NSUInteger index, BOOL *stop) {
        if (@available(macOS 10.13, *)) {
            if (element.removable) {
                return NO;
            }
        }
        return !element.lowPower && !element.headless;
    }];
}

- (id<MTLDevice>)findPreferredDevice {
    if (![iTermAdvancedSettingsModel useLowPowerGPUWhenUnplugged]) {
        BOOL preferLowPower = ![[iTermPowerManager sharedInstance] connectedToPower];
        if (preferLowPower) {
            id<MTLDevice> integratedGPU = [self integratedGPU];
            if (integratedGPU) {
                return integratedGPU;
            }
        } else {
            id<MTLDevice> discreteGPU = [self discreteGPU];
            if (discreteGPU) {
                return discreteGPU;
            }
        }
    }

    return MTLCreateSystemDefaultDevice();
}

- (void)powerManagerStateDidChange:(NSNotification *)notification {
    if (![iTermAdvancedSettingsModel useLowPowerGPUWhenUnplugged]) {
        id<MTLDevice> newPreferredDevice = [self findPreferredDevice];
        if (newPreferredDevice != _preferredDevice) {
            _preferredDevice = newPreferredDevice;
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalDeviceProviderPreferredDeviceDidChangeNotification
                                                                object:newPreferredDevice];
        }
    }
}

@end

NS_ASSUME_NONNULL_END
#endif
