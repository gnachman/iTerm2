//
//  iTermMetalDeviceProvider.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/18.
//
#warning Bring this back
#if 0
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
