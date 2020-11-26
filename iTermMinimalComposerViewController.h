//
//  iTermMinimalComposerViewController.h
//  iTerm2
//
//  Created by George Nachman on 3/31/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermMinimalComposerViewController;

@protocol iTermMinimalComposerViewControllerDelegate<NSObject>
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
            sendCommand:(NSString *)command;
@end

@interface iTermMinimalComposerViewController : NSViewController
@property (nonatomic, weak) id<iTermMinimalComposerViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *stringValue;

- (void)updateFrame;
- (void)makeFirstResponder;

@end

NS_ASSUME_NONNULL_END
