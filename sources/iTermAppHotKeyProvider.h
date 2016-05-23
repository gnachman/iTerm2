#import <Foundation/Foundation.h>

@class iTermAppHotKey;

@interface iTermAppHotKeyProvider : NSObject

@property(nonatomic, readonly) iTermAppHotKey *appHotKey;

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

- (void)invalidate;

@end
