//
//  iTermMinimalComposerViewController.h
//  iTerm2
//
//  Created by George Nachman on 3/31/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TmuxController;
@protocol VT100RemoteHostReading;
@class iTermMinimalComposerViewController;

@protocol iTermMinimalComposerViewControllerDelegate<NSObject>
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
            sendCommand:(NSString *)command
                dismiss:(BOOL)dismiss;
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
         enqueueCommand:(NSString *)command
                dismiss:(BOOL)dismiss;
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
    sendToAdvancedPaste:(NSString *)content;
@end

@interface iTermMinimalComposerViewController : NSViewController
@property (nonatomic, weak) id<iTermMinimalComposerViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *stringValue;

- (void)updateFrame;
- (void)makeFirstResponder;
- (void)setHost:(id<VT100RemoteHostReading>)host
workingDirectory:(NSString *)pwd
          shell:(NSString *)shell
 tmuxController:(TmuxController *)tmuxController;
- (void)setFont:(NSFont *)font;

@end

NS_ASSUME_NONNULL_END
