//
//  iTermShellIntegrationWindowController.h
//  iTerm2
//
//  Created by George Nachman on 12/18/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermShellIntegrationWindowControllerDelegate<NSObject>
- (void)shellIntegrationWindowControllerSendText:(NSString *)text;
- (void)shellIntegrationInferShellWithCompletion:(void (^)(NSString *))completion;
@end

@interface iTermShellIntegrationWindowController : NSWindowController
@property (nonatomic, weak) id<iTermShellIntegrationWindowControllerDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
