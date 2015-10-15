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
                         length:(int)length;

- (IBAction)cancel:(id)sender;
- (void)updateFrame;
- (void)close;

@end
