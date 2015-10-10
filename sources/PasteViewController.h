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

@interface PasteViewController : NSViewController {
    IBOutlet NSProgressIndicator *progressIndicator_;
    int totalLength_;
    int remainingLength_;
    PasteContext *pasteContext_;
    __weak id<PasteViewControllerDelegate> delegate_;
}

@property (nonatomic, assign) __weak id<PasteViewControllerDelegate> delegate;

- (instancetype)initWithContext:(PasteContext *)pasteContext_
               length:(int)length;

- (IBAction)cancel:(id)sender;
@property (nonatomic) int remainingLength;
- (void)updateFrame;
- (void)close;

@end
