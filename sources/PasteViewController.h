//
//  PasteViewController.h
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import <Cocoa/Cocoa.h>

@class PasteContext;

@protocol PasteViewControllerDelegate <NSObject>

- (void)pasteViewControllerDidCancel;

@end

@interface PasteViewController : NSViewController

@property(nonatomic, assign) id<PasteViewControllerDelegate> delegate;
@property(nonatomic, assign) int remainingLength;

- (instancetype)initWithContext:(PasteContext *)pasteContext_
                         length:(int)length
                           mini:(BOOL)mini NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (IBAction)cancel:(id)sender;
- (void)updateFrame;
- (void)closeWithCompletion:(void (^)(void))completion;

@end
