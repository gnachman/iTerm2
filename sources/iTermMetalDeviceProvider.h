//
//  iTermMetalDeviceProvider.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/18.
//
#if ENABLE_LOW_POWER_GPU_DETECTION
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermMetalDeviceProviderPreferredDeviceDidChangeNotification;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalDeviceProvider : NSObject

@property (nonatomic, readonly, strong) id<MTLDevice> preferredDevice;

+ (instancetype)sharedInstance;

@end

NS_ASSUME_NONNULL_END
#endif
