//
//  iTermStatusBarProgressComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/18.
//

#import "iTermStatusBarProgressComponent.h"

#import "PasteViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermStatusBarProgressComponent()<PasteViewControllerDelegate>
@end

@implementation iTermStatusBarProgressComponent {
    PasteViewController *_viewController;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 125;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    assert(view == _viewController.view);
    NSRect rect = view.frame;
    rect.size.width = width;
    rect.size.height = 18;
    view.frame = rect;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return 200;
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

#pragma mark - iTermStatusBarComponent

- (NSString *)statusBarComponentShortDescription {
    return @"Progress Indicator";
}

- (NSString *)statusBarComponentDetailedDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"Generic progress indicator";
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    return @[];
}

- (id)statusBarComponentExemplar {
    [self doesNotRecognizeSelector:_cmd];
    return @"[=== ]";
}

- (NSView *)statusBarComponentCreateView {
    if (!_viewController) {
        _viewController = [[PasteViewController alloc] initWithContext:self.pasteContext
                                                                length:self.bufferLength
                                                                  mini:YES];
        _viewController.delegate = self;
    }
    return _viewController.view;
}

- (CGFloat)statusBarComponentVerticalOffset {
    return 0;
}

- (void)setRemainingLength:(int)remainingLength {
    _viewController.remainingLength = remainingLength;
}

- (int)remainingLength {
    return _viewController.remainingLength;
}

#pragma mark - PasteViewControllerDelegate

- (void)pasteViewControllerDidCancel {
    [self.progressDelegate statusBarProgressComponentDidCancel];
}

@end

NS_ASSUME_NONNULL_END
