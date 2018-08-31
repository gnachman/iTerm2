#import <Cocoa/Cocoa.h>

@class iTermLibController;

@interface iTermLibApplication : NSObject

+ (instancetype)sharedApplication;

@property (readonly) iTermLibController *delegate;

@end
