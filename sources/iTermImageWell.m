//
//  iTermImageWell.m
//  iTerm2
//
//  Created by George Nachman on 12/17/14.
//
//

#import "iTermImageWell.h"

@interface iTermImageWell () {
    NSVisualEffectView *_effectView;
    NSTextField       *_overlayLabel;
}
@end

@implementation iTermImageWell

- (void)awakeFromNib {
    [super awakeFromNib];
    self.wantsLayer = YES;
    self.layer.borderColor = [[NSColor whiteColor] CGColor];
    self.layer.borderWidth = 2.0;
    self.layer.cornerRadius = 6.0;

    _effectView = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    _effectView.material = NSVisualEffectMaterialHUDWindow;
    _effectView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _effectView.wantsLayer = YES;
    _effectView.layer.cornerRadius = 4.0;
    [self addSubview:_effectView];

    _overlayLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _overlayLabel.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    _overlayLabel.textColor = [NSColor textColor];
    _overlayLabel.alignment = NSTextAlignmentCenter;
    _overlayLabel.drawsBackground = NO;
    _overlayLabel.bordered = NO;
    _overlayLabel.editable = NO;
    _overlayLabel.selectable = NO;
    [self addSubview:_overlayLabel];

    [self updateOverlayText];
}

- (void)layout {
    [super layout];

    const CGFloat paddingX = 4.0;
    const CGFloat paddingY = 4.0;
    const NSSize textSize = [_overlayLabel fittingSize];
    const NSRect bounds = self.bounds;
    const NSRect labelFrame = NSMakeRect((NSWidth(bounds) - textSize.width) / 2,
                                   (NSHeight(bounds) - textSize.height) / 2,
                                   textSize.width,
                                   textSize.height);

    const NSRect effectFrame = NSMakeRect(labelFrame.origin.x - paddingX,
                                          labelFrame.origin.y - paddingY,
                                          labelFrame.size.width + 2 * paddingX,
                                          labelFrame.size.height + 2 * paddingY);

    _overlayLabel.frame = labelFrame;
    _effectView.frame = effectFrame;

    _overlayLabel.hidden = bounds.size.width < 250;
    _effectView.hidden = bounds.size.width < 250;
}

- (void)setImage:(NSImage *)image {
    [super setImage:image];
    [self updateOverlayText];
}

- (void)updateOverlayText {
    if (self.image == nil) {
        _overlayLabel.stringValue = @"No Image Selected\u2009—\u2009Click to set";
    }
    else {
        _overlayLabel.stringValue = @"Click to change";
    }
    [self setNeedsLayout:YES];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)draggingInfo {
    if (![super performDragOperation:draggingInfo]) {
        return NO;
    }

    NSPasteboard *pasteboard = [draggingInfo draggingPasteboard];
    NSString *theString = [pasteboard stringForType:NSPasteboardTypeFileURL];

    if (theString) {
        NSData *data = [theString dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *filenames =
            [NSPropertyListSerialization propertyListWithData:data
                                                      options:NSPropertyListImmutable
                                                       format:nil
                                                        error:nil];

        if (filenames.count) {
            [_delegate imageWellDidPerformDropOperation:self filename:filenames[0]];
        }
    }

    return YES;
}

// If we don't override mouseDown: then mouseUp: never gets called.
- (void)mouseDown:(NSEvent *)theEvent {
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (theEvent.clickCount == 1) {
        [_delegate imageWellDidClick:self];
    }
}

- (BOOL)clipsToBounds {
    return YES;
}

@end

