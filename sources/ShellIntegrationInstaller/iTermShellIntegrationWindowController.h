//
//  iTermShellIntegrationWindowController.h
//  iTerm2
//
//  Created by George Nachman on 12/18/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermExpect;

@protocol iTermShellIntegrationWindowControllerDelegate<NSObject>
- (void)shellIntegrationWindowControllerSendText:(NSString *)text;
- (iTermExpect *)shellIntegrationExpect;
@end

@interface iTermShellIntegrationWindowController : NSWindowController
@property (nonatomic, weak) id<iTermShellIntegrationWindowControllerDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
