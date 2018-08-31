#import "iTermLibApplication.h"

#import "iTermLibController.h"

static iTermLibApplication* _gSharedApplication;

@implementation iTermLibApplication

+ (instancetype)sharedApplication
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _gSharedApplication = [[iTermLibApplication alloc] init];
    });
    
    return _gSharedApplication;
}

- (iTermLibController*)delegate
{
    return iTermLibController.sharedController;
}

@end
