//
//  iTermScriptTemplatePickerWindowController.m
//  iTerm2
//
//  Created by George Nachman on 4/26/18.
//

#import "iTermScriptTemplatePickerWindowController.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"

@class iTermSelectableBox;

@protocol iTermSelectableBoxDelegate<NSObject>

- (void)didSelectSelectableBox:(iTermSelectableBox *)box;

@end

@interface iTermSelectableBox : NSBox

@property (nonatomic, weak) IBOutlet id<iTermSelectableBoxDelegate> delegate;

@end

@implementation iTermSelectableBox

- (void)mouseDown:(NSEvent *)event {
    [self setFillColor:[NSColor selectedMenuItemColor] textColor:[NSColor whiteColor] inView:self];
}

- (void)setFillColor:(NSColor *)fillColor textColor:(NSColor *)textColor inView:(NSView *)containerView {
    self.fillColor = fillColor;
    for (NSView *view in containerView.subviews) {
        NSTextField *textField = [NSTextField castFrom:view];
        if (textField) {
            textField.textColor = textColor;
        } else {
            [self setFillColor:fillColor textColor:textColor inView:view];
        }
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (event.clickCount == 1) {
        [self.delegate didSelectSelectableBox:self];
    } else {
        [self setFillColor:[NSColor gridColor] textColor:[NSColor blackColor] inView:self];
    }
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor arrowCursor]];

}

@end

@interface iTermScriptTemplatePickerWindowController ()<iTermSelectableBoxDelegate>

@end

@implementation iTermScriptTemplatePickerWindowController {
    IBOutlet NSView *_environmentView;
    IBOutlet NSView *_templateView;
    IBOutlet iTermSelectableBox *_basic;
    IBOutlet iTermSelectableBox *_pyenv;
    IBOutlet iTermSelectableBox *_simple;
    IBOutlet iTermSelectableBox *_daemon;
    NSCursor *_cursor;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    _cursor = [NSCursor arrowCursor];
    __weak __typeof(self) weakSelf = self;
    NSCursor *cursor = _cursor;
    [self.window.contentView enumerateHierarchy:^(NSView *view) {
        [weakSelf.window.contentView addCursorRect:view.bounds cursor:cursor];
    }];
    [_basic addTrackingRect:_basic.bounds owner:_basic userData:NULL assumeInside:NO];
    [_pyenv addTrackingRect:_pyenv.bounds owner:_pyenv userData:NULL assumeInside:NO];

    _cursor.onMouseEntered = YES;
}

- (void)showTemplateView {
    NSRect frame = _templateView.frame;
    frame.origin.x = _environmentView.frame.size.width;
    frame.origin.y = _environmentView.frame.origin.y;
    _templateView.frame = frame;
    [self.window.contentView addSubview:_templateView];

    [NSView animateWithDuration:0.25
                     animations:^{
                         NSRect frame = self->_environmentView.frame;
                         frame.origin.x -= frame.size.width;
                         self->_environmentView.animator.frame = frame;

                         frame = self->_templateView.frame;
                         frame.origin.x = 0;
                         self->_templateView.animator.frame = frame;
                     } completion:nil];
}

#pragma mark - Actions

- (void)basicEnvironment:(id)sender {
    _selectedEnvironment = iTermScriptEnvironmentBasic;
    [self showTemplateView];
}

- (void)fullEnvironment:(id)sender {
    _selectedEnvironment = iTermScriptEnvironmentPrivateEnvironment;
    [self showTemplateView];
}

- (void)simpleTemplate:(id)sender {
    _selectedTemplate = iTermScriptTemplateSimple;
    [NSApp stopModal];
}

- (void)daemonTemplate:(id)sender {
    _selectedTemplate = iTermScriptTemplateDaemon;
    [NSApp stopModal];
}

- (IBAction)cancel:(id)sender {
    _selectedTemplate = iTermScriptTemplateNone;
    _selectedEnvironment = iTermScriptEnvironmentNone;
    [NSApp stopModal];
}

- (void)didSelectSelectableBox:(iTermSelectableBox *)box {
    if (box == _basic) {
        [self basicEnvironment:box];
    } else if (box == _pyenv) {
        [self fullEnvironment:box];
    } else if (box == _simple) {
        [self simpleTemplate:box];
    } else if (box == _daemon) {
        [self daemonTemplate:box];
    }
}

@end
