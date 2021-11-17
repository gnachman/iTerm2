//
//  iTermMinimalComposerViewController.h
//  iTerm2
//
//  Created by George Nachman on 3/31/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TmuxController;
@class VT100RemoteHost;
@class iTermMinimalComposerViewController;

@protocol iTermMinimalComposerViewControllerDelegate<NSObject>
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
            sendCommand:(NSString *)command;
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
    sendToAdvancedPaste:(NSString *)content;
@end

@interface iTermMinimalComposerViewController : NSViewController
@property (nonatomic, weak) id<iTermMinimalComposerViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *stringValue;

- (void)updateFrame;
- (void)makeFirstResponder;
- (void)setHost:(VT100RemoteHost *)host
workingDirectory:(NSString *)pwd
          shell:(NSString *)shell
 tmuxController:(TmuxController *)tmuxController;
- (void)setFont:(NSFont *)font;

@end

NS_ASSUME_NONNULL_END
