//
//  iTermStatusBarSetupCollectionViewItem.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarSetupCollectionViewItem.h"
#import "NSView+iTerm.h"

@interface iTermStatusBarSetupCollectionViewItem ()

@end

@implementation iTermStatusBarSetupCollectionViewItem {
    IBOutlet NSBox *_box;
    IBOutlet NSView *_boxContent;
    IBOutlet NSTextField *_description;
    NSEdgeInsets _textFieldInsets;
    CGFloat _boxMinY;
    CGFloat _descriptionMinY;
    NSColor *_backgroundColor;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.view.wantsLayer = YES;
    self.view.autoresizesSubviews = NO;
    self.textField.superview.autoresizesSubviews = NO;

    const NSRect textFieldFrame = self.textField.frame;
    // Minus one because the box has a content view inset by 1 in both margins
    _textFieldInsets.left =  textFieldFrame.origin.x - 1;
    _textFieldInsets.right = _textFieldInsets.left;
    _textFieldInsets.top = (_box.frame.size.height - self.textField.frame.size.height) / 2 - 1;
    _textFieldInsets.bottom = _textFieldInsets.top;
    _boxMinY = _box.frame.origin.y;
    _descriptionMinY = _description.frame.origin.y;
    [self updateFillColor];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    _backgroundColor = backgroundColor;
    [self updateFillColor];
}

- (NSColor *)backgroundColor {
    return _backgroundColor;
}

- (void)sizeToFit {
    [self view];

    _description.hidden = self.hideDetail;

    NSRect textFieldFrame = self.textField.frame;
    textFieldFrame.size = self.textField.fittingSize;
    self.textField.frame = [self.view retinaRoundRect:textFieldFrame];

    NSRect descriptionFrame = _description.frame;
    descriptionFrame.size = _description.fittingSize;
    _description.frame = [self.view retinaRoundRect:descriptionFrame];

    const CGFloat descriptionWidth = self.hideDetail ? 0 : _description.frame.size.width;
    const NSSize textFieldSize = NSMakeSize(MAX(textFieldFrame.size.width, descriptionWidth),
                                            textFieldFrame.size.height);

    const CGFloat totalWidth = textFieldSize.width + _textFieldInsets.left + _textFieldInsets.right;

    const CGFloat boxMinY = self.hideDetail ? 0 : _boxMinY;
    self.view.frame = [self.view retinaRoundRect:NSMakeRect(self.view.frame.origin.x,
                                                            self.view.frame.origin.y,
                                                            totalWidth,
                                                            boxMinY + _box.frame.size.height)];

    const CGFloat boxWidth = textFieldFrame.size.width + _textFieldInsets.left + _textFieldInsets.right;
    _box.frame = [self.view retinaRoundRect:NSMakeRect(round((totalWidth - boxWidth) / 2),
                                                       boxMinY,
                                                       boxWidth,
                                                       textFieldSize.height + _textFieldInsets.top + _textFieldInsets.bottom)];
    self.textField.frame = [self.view retinaRoundRect:NSMakeRect(_textFieldInsets.left,
                                                                 _textFieldInsets.bottom,
                                                                 textFieldSize.width,
                                                                 textFieldSize.height)];
    if (!self.hideDetail) {
        _description.frame = [self.view retinaRoundRect:NSMakeRect(_textFieldInsets.left,
                                                                   _descriptionMinY,
                                                                   textFieldSize.width,
                                                                   _description.frame.size.height)];
    }
}

- (void)setDetailText:(NSString *)detailText {
    _detailText = detailText.copy;
    _description.stringValue = detailText;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self updateFillColor];
}

- (void)setHighlightState:(NSCollectionViewItemHighlightState)highlightState {
    [super setHighlightState:highlightState];
    [self updateFillColor];
}

- (void)updateFillColor {
    if (!self.hideDetail) {
        return;
    }
    if (self.selected) {
        _box.fillColor = [NSColor selectedControlColor];
    } else {
        switch (self.highlightState) {
            case NSCollectionViewItemHighlightNone:
                _box.fillColor = _backgroundColor ?: [NSColor controlColor];
                break;

            case NSCollectionViewItemHighlightAsDropTarget:
            case NSCollectionViewItemHighlightForSelection:
                _box.fillColor = [NSColor controlHighlightColor];
                break;
            case NSCollectionViewItemHighlightForDeselection:
                _box.fillColor = [NSColor controlLightHighlightColor];
                break;
        }
    }
    [self.view setNeedsDisplay:YES];
}

@end
