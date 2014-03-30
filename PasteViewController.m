//
//  PasteViewController.m
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import "PasteViewController.h"
#import "PasteContext.h"

static float kAnimationDuration = 0.25;

@implementation PasteViewController

@synthesize delegate = delegate_;

- (id)initWithContext:(PasteContext *)pasteContext
               length:(int)length {
    self = [super initWithNibName:@"PasteView" bundle:nil];
    if (self) {
        [self view];

        // Fix up frames beacuse the view is flipped.
        for (NSView *view in [self.view subviews]) {
            NSRect frame = [view frame];
            frame.origin.y = NSMaxY([self.view bounds]) - NSMaxY([view frame]);
            [view setFrame:frame];
        }
        pasteContext_ = [pasteContext retain];
        totalLength_ = remainingLength_ = length;
    }
    return self;
}

- (void)dealloc {
    [pasteContext_ release];
    [super dealloc];
}

- (IBAction)cancel:(id)sender {
    [delegate_ pasteViewControllerDidCancel];
}

- (void)setRemainingLength:(int)remainingLength {
    remainingLength_ = remainingLength;
    double ratio = remainingLength;
    ratio /= (double)totalLength_;
    [progressIndicator_ setDoubleValue:1.0 - ratio];
    [progressIndicator_ displayIfNeeded];
}

- (void)updateFrame {
    NSRect newFrame = self.view.frame;
    newFrame.origin.y = self.view.superview.frame.size.height;
    self.view.frame = newFrame;

    newFrame.origin.y += self.view.frame.size.height;
    newFrame = NSMakeRect(self.view.frame.origin.x,
                          self.view.superview.frame.size.height - self.view.frame.size.height,
                          self.view.frame.size.width,
                          self.view.frame.size.height);
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    [[self.view animator] setFrame:newFrame];
}

- (void)close {
    NSRect newFrame = self.view.frame;
    newFrame.origin.y = self.view.superview.frame.size.height;
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    [[self.view animator] setFrame:newFrame];
    [self.view performSelector:@selector(removeFromSuperview) withObject:nil afterDelay:kAnimationDuration];
}

@end
