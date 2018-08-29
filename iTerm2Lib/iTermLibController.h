#import <Cocoa/Cocoa.h>

#import "iTermLibSessionController.h"

@class PTYSession;
@class iTermLibController;

@protocol iTermLibControllerDelegate<NSObject>

- (void)controller:(iTermLibController*)controller shouldRemoveSessionView:(iTermLibSessionController*)session;

@optional
- (void)controller:(iTermLibController*)controller sessionDidClose:(iTermLibSessionController*)session;
- (void)controller:(iTermLibController*)controller nameOfSession:(iTermLibSessionController*)session didChangeTo:(NSString*)newName;

@end

@interface iTermLibController : NSObject<iTermLibSessionDelegate>

+ (instancetype)sharedController;

@property (readonly, copy) NSArray<iTermLibSessionController*>* sessions;
@property (readonly) iTermLibSessionController* activeSession;
@property (assign) id<iTermLibControllerDelegate> delegate;
@property (assign) BOOL broadcasting;

- (iTermLibSessionController*)createSessionWithProfile:(Profile*)profile command:(NSString*)command initialSize:(NSSize)initialSize;

@end
