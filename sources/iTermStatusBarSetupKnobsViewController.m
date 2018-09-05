//
//  iTermStatusBarSetupKnobsViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarSetupKnobsViewController.h"

#import "iTermStatusBarKnobCheckboxViewController.h"
#import "iTermStatusBarKnobColorViewController.h"
#import "iTermStatusBarKnobNumericViewController.h"
#import "iTermStatusBarKnobTextViewController.h"
#import "NSArray+iTerm.h"

static const CGFloat iTermStatusBarSetupPopoverMargin = 5;

@interface iTermStatusBarSetupKnobsViewController ()

@end

static NSViewController<iTermStatusBarKnobViewController> *iTermNewViewControllerForKnob(iTermStatusBarComponentKnob *knob) {
    switch (knob.type) {
        case iTermStatusBarComponentKnobTypeCheckbox:
            return [[iTermStatusBarKnobCheckboxViewController alloc] init];

        case iTermStatusBarComponentKnobTypeText:
            return [[iTermStatusBarKnobTextViewController alloc] init];

        case iTermStatusBarComponentKnobTypeDouble:
            return [[iTermStatusBarKnobNumericViewController alloc] init];

        case iTermStatusBarComponentKnobTypeColor:
            return [[iTermStatusBarKnobColorViewController alloc] init];
            
        default:
            return nil;
    }
}

@implementation iTermStatusBarSetupKnobsViewController {
    NSArray<NSViewController<iTermStatusBarKnobViewController> *> *_viewControllers;
    CGSize _size;
    CGFloat _maxControlOffset;
    id<iTermStatusBarComponent> _component;
}

- (instancetype)initWithComponent:(id<iTermStatusBarComponent>)component {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _component = component;
        _knobs = [component statusBarComponentKnobs].reverseObjectEnumerator.allObjects;
        NSDictionary *knobValues = component.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
        [_knobs enumerateObjectsUsingBlock:^(iTermStatusBarComponentKnob * _Nonnull knob, NSUInteger idx, BOOL * _Nonnull stop) {
            knob.value = knobValues[knob.key] ?: knob.value;
        }];
        _size.height = iTermStatusBarSetupPopoverMargin * 2;
        __block CGFloat maxControlWidth = 0;
        _viewControllers = [_knobs mapWithBlock:^id(iTermStatusBarComponentKnob *knob) {
            NSViewController<iTermStatusBarKnobViewController> *vc = iTermNewViewControllerForKnob(knob);
            [self addChildViewController:vc];
            [vc view];
            [vc setDescription:knob.labelText placeholder:knob.placeholder];
            vc.value = knob.value;
            const CGFloat controlWidth = vc.view.frame.size.width - vc.controlOffset;
            maxControlWidth = MAX(controlWidth, maxControlWidth);
            self->_size.height += vc.view.frame.size.height;
            self->_maxControlOffset = MAX(self->_maxControlOffset, vc.controlOffset);
            return vc;
        }];
        _size.width = MAX(150, _maxControlOffset + maxControlWidth + iTermStatusBarSetupPopoverMargin * 2);
        if (_viewControllers.count >= 1) {
            _size.height += 5 * (_viewControllers.count - 1);
        }
    }

    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, _size.width, _size.height)];
}

- (NSSize)preferredContentSize {
    return _size;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    for (NSViewController<iTermStatusBarKnobViewController> *vc in _viewControllers) {
        [self.view addSubview:vc.view];
    }
    [self layoutSubviews];
}

- (void)layoutSubviews {
    CGFloat y = iTermStatusBarSetupPopoverMargin;
    for (NSViewController<iTermStatusBarKnobViewController> *vc in _viewControllers) {
        const CGFloat x = _maxControlOffset - vc.controlOffset + iTermStatusBarSetupPopoverMargin;
        vc.view.frame = NSMakeRect(x, y, vc.view.frame.size.width, vc.view.frame.size.height);
        y += vc.view.frame.size.height + 5;
    }
}

- (void)viewWillDisappear {
    [self commit];
}

- (void)commit {
    for (NSInteger i = 0; i < _knobs.count; i++) {
        id value = _viewControllers[i].value;
        [_knobs[i] setValue:value];
    }
    [_component statusBarComponentSetKnobValues:self.knobValues];
}

- (NSDictionary *)knobValues {
    NSArray *keys = [_knobs mapWithBlock:^id(iTermStatusBarComponentKnob *anObject) {
        return anObject.value ? anObject.key : nil;
    }];
    NSArray *values = [_knobs mapWithBlock:^id(iTermStatusBarComponentKnob *anObject) {
        return anObject.value;
    }];
    return [NSDictionary dictionaryWithObjects:values forKeys:keys];
}

@end
