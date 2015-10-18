#import "CPKSelectionView.h"
#import "CPKColorComponentSliderView.h"
#import "CPKGradientView.h"
#import "CPKAlphaSliderView.h"
#import "NSColor+CPK.h"

static const CGFloat kLeftMargin = 8;
static const CGFloat kRightMargin = 8;
static const CGFloat kTopMargin = 8;
static const CGFloat kGradientHeight = 120;
static const CGFloat kMarginBetweenGradientAndColorComponentSlider = 8;
static const CGFloat kMarginBetweenPopupButtonAndGradient = 2;
static const CGFloat kColorComponentSliderHeight = 24;
static const CGFloat kAlphaSliderHeight = 12;
static const CGFloat kMarginBetweenTextFields = 4;
static const CGFloat kMarginBetweenLastSliderAndTextFields = 8;
static const CGFloat kColorTextFieldWidth = 32;
static const CGFloat kMarginBetweenTextFieldAndLabel = 0;
static const CGFloat kBottomMargin = 0;
static const CGFloat kMarginBetweenSliders = 8;

typedef NS_ENUM(NSInteger, CPKRGBViewMode) {
    kCPKRGBViewModeHSBWithHueSliderTag,
    kCPKRGBViewModeHSBWithBrightnessSliderTag,
    kCPKRGBViewModeHSBWithSaturationSliderTag,
    kCPKRGBViewModeRGBWithRedSliderTag,
    kCPKRGBViewModeRGBWithGreenSliderTag,
    kCPKRGBViewModeRGBWithBlueSliderTag,
};

@interface CPKSelectionView() <NSTextFieldDelegate>
@property(nonatomic) NSPopUpButton *modeButton;
@property(nonatomic) CPKGradientView *gradientView;
@property(nonatomic) CPKColorComponentSliderView *colorComponentSliderView;
@property(nonatomic) CPKAlphaSliderView *alphaSliderView;
@property(nonatomic, copy) void (^block)(NSColor *);
@property(nonatomic) NSTextField *hexTextField;
@property(nonatomic) NSTextField *redTextField;
@property(nonatomic) NSTextField *greenTextField;
@property(nonatomic) NSTextField *blueTextField;
@property(nonatomic) NSTextField *alphaTextField;
@property(nonatomic) CGFloat desiredHeight;
@property(nonatomic) BOOL alphaAllowed;
@end

@implementation CPKSelectionView

- (instancetype)initWithFrame:(NSRect)frameRect
                        block:(void (^)(NSColor *))block
                        color:(NSColor *)color
                 alphaAllowed:(BOOL)alphaAllowed {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.autoresizesSubviews = NO;

        _selectedColor = color;
        self.alphaAllowed = alphaAllowed;

        NSRect frame;
        frame = NSMakeRect(kLeftMargin,
                           kTopMargin,
                           NSWidth(frameRect) - kRightMargin - kLeftMargin,
                           0);
        self.modeButton = [[NSPopUpButton alloc] initWithFrame:frame];
        [self.modeButton setTarget:self];
        [self.modeButton setAction:@selector(modeDidChange:)];

        [self.modeButton addItemWithTitle:@"HSB with Hue Slider"];
        [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeHSBWithHueSliderTag];
        [self.modeButton addItemWithTitle:@"HSB with Brightness Slider"];
        [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeHSBWithBrightnessSliderTag];
        [self.modeButton addItemWithTitle:@"HSB with Saturation Slider"];
        [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeHSBWithSaturationSliderTag];

        [self.modeButton addItemWithTitle:@"RGB with Red Slider"];
        [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeRGBWithRedSliderTag];
        [self.modeButton addItemWithTitle:@"RGB with Green Slider"];
        [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeRGBWithGreenSliderTag];
        [self.modeButton addItemWithTitle:@"RGB with Blue Slider"];
        [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeRGBWithBlueSliderTag];
        
        [self.modeButton sizeToFit];
        frame = self.modeButton.frame;
        frame.size.width = NSWidth(frameRect) - kRightMargin - kLeftMargin;
        self.modeButton.frame = frame;

        frame = NSMakeRect(kLeftMargin,
                           NSMaxY(self.modeButton.frame) + kMarginBetweenPopupButtonAndGradient,
                           NSWidth(frameRect) - kRightMargin - kLeftMargin,
                           kGradientHeight);
        __weak __typeof(self) weakSelf = self;
        self.gradientView =
            [[CPKGradientView alloc] initWithFrame:frame
                                              type:kCPKGradientViewTypeSaturationBrightness
                                             block:^(NSColor *newColor) {
                                                 [weakSelf setColorFromGradient:newColor];
                                             }];

        frame = NSMakeRect(kLeftMargin,
                           NSMaxY(self.gradientView.frame) + kMarginBetweenGradientAndColorComponentSlider,
                           NSWidth(frameRect) - kRightMargin - kLeftMargin,
                           kColorComponentSliderHeight);

        self.colorComponentSliderView =
            [[CPKColorComponentSliderView alloc] initWithFrame:frame
                                                         color:color
                                                          type:kCPKColorComponentSliderTypeHue
                                                         block:^(CGFloat newValue) {
                                                             [weakSelf setSliderValue:newValue];
                                                         }];
        CGFloat y = NSMaxY(self.colorComponentSliderView.frame) + kMarginBetweenLastSliderAndTextFields;

        if (alphaAllowed) {
            frame.origin.y = NSMaxY(frame) + kMarginBetweenSliders;
            frame.size.height = kAlphaSliderHeight;
            self.alphaSliderView = [[CPKAlphaSliderView alloc] initWithFrame:frame
                                                                       alpha:color.alphaComponent
                                                                       color:color
                                                                       block:^(CGFloat newAlpha) {
                    [weakSelf setAlpha:newAlpha];
                }];
            y = NSMaxY(self.alphaSliderView.frame) + kMarginBetweenLastSliderAndTextFields;
        }

        self.gradientView.selectedColor = color;

        CGFloat x = NSMaxX(self.frame) - kRightMargin;
        if (alphaAllowed) {
            self.alphaTextField =
                [[NSTextField alloc] initWithFrame:NSMakeRect(x - kColorTextFieldWidth,
                                                              y,
                                                              kColorTextFieldWidth,
                                                              24)];
            self.alphaTextField.delegate = self;
            x -= self.alphaTextField.frame.size.width + kMarginBetweenTextFields;
        }
        self.blueTextField =
            [[NSTextField alloc] initWithFrame:NSMakeRect(x - kColorTextFieldWidth,
                                                          y,
                                                          kColorTextFieldWidth,
                                                          24)];
        self.blueTextField.delegate = self;
        x -= self.blueTextField.frame.size.width + kMarginBetweenTextFields;

        self.greenTextField =
            [[NSTextField alloc] initWithFrame:NSMakeRect(x - kColorTextFieldWidth,
                                                          y,
                                                          kColorTextFieldWidth,
                                                          24)];
        self.greenTextField.delegate = self;
        x -= self.greenTextField.frame.size.width + kMarginBetweenTextFields;

        self.redTextField = [[NSTextField alloc] initWithFrame:NSMakeRect(x - kColorTextFieldWidth,
                                                                          y,
                                                                          kColorTextFieldWidth,
                                                                          24)];
        self.redTextField.delegate = self;
        x -= self.redTextField.frame.size.width + kMarginBetweenTextFields;

        self.hexTextField =
            [[NSTextField alloc] initWithFrame:NSMakeRect(kLeftMargin,
                                                          y,
                                                          NSMinX(self.redTextField.frame) -
                                                              kLeftMargin -
                                                              kMarginBetweenTextFields,
                                                          24)];
        self.hexTextField.delegate = self;

        [self updateTextFieldsForColor:color];
        self.subviews = @[ self.modeButton,
                           self.gradientView,
                           self.colorComponentSliderView,
                           self.hexTextField,
                           self.redTextField,
                           self.greenTextField,
                           self.blueTextField ];
        if (alphaAllowed) {
            [self addSubview:self.alphaTextField];
            [self addSubview:self.alphaSliderView];
        }

        [self addLabel:@"Hex" belowView:self.hexTextField];
        [self addLabel:@"R" belowView:self.redTextField];
        [self addLabel:@"G" belowView:self.greenTextField];
        NSView *label = [self addLabel:@"B" belowView:self.blueTextField];
        if (alphaAllowed) {
            label = [self addLabel:@"A" belowView:self.alphaTextField];
        }
        self.desiredHeight = NSMaxY(label.frame) + kBottomMargin;

        self.block = block;
    }
    return self;
}

- (NSTextField *)addLabel:(NSString *)string belowView:(NSView *)view {
    NSTextField *label =
        [[NSTextField alloc] initWithFrame:NSMakeRect(NSMinX(view.frame),
                                                      NSMaxY(view.frame) +
                                                          kMarginBetweenTextFieldAndLabel,
                                                      NSWidth(view.bounds),
                                                      24)];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.stringValue = string;
    label.alignment = NSCenterTextAlignment;
    [self addSubview:label];
    return label;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setSliderValue:(CGFloat)newValue {
    switch (self.modeButton.selectedTag) {
        case kCPKRGBViewModeHSBWithHueSliderTag:
            _selectedColor = [NSColor cpk_colorWithHue:newValue
                                            saturation:self.selectedColor.saturationComponent
                                            brightness:self.selectedColor.brightnessComponent
                                                 alpha:self.selectedColor.alphaComponent];
            self.gradientView.hue = newValue;
            break;
        case kCPKRGBViewModeHSBWithSaturationSliderTag:
            _selectedColor = [NSColor cpk_colorWithHue:self.selectedColor.hueComponent
                                            saturation:newValue
                                            brightness:self.selectedColor.brightnessComponent
                                                 alpha:self.selectedColor.alphaComponent];
            self.gradientView.saturation = newValue;
            break;
        case kCPKRGBViewModeHSBWithBrightnessSliderTag:
            _selectedColor = [NSColor cpk_colorWithHue:self.selectedColor.hueComponent
                                            saturation:self.selectedColor.saturationComponent
                                            brightness:newValue
                                                 alpha:self.selectedColor.alphaComponent];
            self.gradientView.brightness = newValue;
            break;
        case kCPKRGBViewModeRGBWithRedSliderTag:
            _selectedColor = [NSColor cpk_colorWithRed:newValue
                                                 green:self.selectedColor.greenComponent
                                                  blue:self.selectedColor.blueComponent
                                                 alpha:self.selectedColor.alphaComponent];
            self.gradientView.red = newValue;
            break;
        case kCPKRGBViewModeRGBWithGreenSliderTag:
            _selectedColor = [NSColor cpk_colorWithRed:self.selectedColor.redComponent
                                                 green:newValue
                                                  blue:self.selectedColor.blueComponent
                                                 alpha:self.selectedColor.alphaComponent];
            self.gradientView.green = newValue;
            break;
        case kCPKRGBViewModeRGBWithBlueSliderTag:
            _selectedColor = [NSColor cpk_colorWithRed:self.selectedColor.redComponent
                                                 green:self.selectedColor.greenComponent
                                                  blue:newValue
                                                 alpha:self.selectedColor.alphaComponent];
            self.gradientView.blue = newValue;
            break;
    }
    self.alphaSliderView.color = _selectedColor;
    [self.alphaSliderView setNeedsDisplay:YES];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_gradientView setNeedsDisplay:YES];
    });
    [self updateTextFieldsForColor:self.selectedColor];
    self.block(self.selectedColor);
}

- (void)setAlpha:(CGFloat)newAlpha {
    _selectedColor = [NSColor cpk_colorWithHue:self.selectedColor.hueComponent
                                    saturation:self.selectedColor.saturationComponent
                                    brightness:self.selectedColor.brightnessComponent
                                         alpha:newAlpha];
    [self updateTextFieldsForColor:self.selectedColor];
    self.block(self.selectedColor);
}

- (void)setColorFromGradient:(NSColor *)newColor {
    if (self.alphaAllowed && _selectedColor) {
        _selectedColor =
            [newColor colorWithAlphaComponent:_selectedColor.alphaComponent];
    } else {
        _selectedColor = newColor;
    }
    [self.colorComponentSliderView setGradientColor:newColor];
    self.alphaSliderView.color = newColor;
    [self.alphaSliderView setNeedsDisplay:YES];
    [self updateTextFieldsForColor:_selectedColor];
    self.block(_selectedColor);
}

- (void)setSelectedColor:(NSColor *)selectedColor {
    if (!self.alphaAllowed) {
        selectedColor = [selectedColor colorWithAlphaComponent:1];
    }
    _selectedColor = selectedColor;
    [self.gradientView setSelectedColor:selectedColor];
    self.colorComponentSliderView.color = selectedColor;
    self.alphaSliderView.color = selectedColor;
    self.alphaSliderView.selectedValue = selectedColor.alphaComponent;
    [self.alphaSliderView setNeedsDisplay:YES];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_gradientView setNeedsDisplay:YES];
    });
    [self updateTextFieldsForColor:self.selectedColor];
    self.block(selectedColor);
}

- (void)updateTextFieldsForColor:(NSColor *)color {
    self.hexTextField.stringValue = [NSString stringWithFormat:@"%02x%02x%02x",
                                        (int)(color.redComponent * 255),
                                        (int)(color.greenComponent * 255),
                                        (int)(color.blueComponent * 255)];
    self.redTextField.stringValue =
        [NSString stringWithFormat:@"%d", (int)(color.redComponent * 255)];
    self.greenTextField.stringValue =
        [NSString stringWithFormat:@"%d", (int)(color.greenComponent * 255)];
    self.blueTextField.stringValue =
        [NSString stringWithFormat:@"%d", (int)(color.blueComponent * 255)];
    if (self.alphaAllowed) {
        self.alphaTextField.stringValue =
            [NSString stringWithFormat:@"%d", (int)(color.alphaComponent * 255)];
    }
}

- (void)sizeToFit {
    NSRect frame = NSMakeRect(NSMinX(self.frame),
                              NSMinY(self.frame),
                              NSWidth(self.bounds),
                              _desiredHeight);
    self.frame = frame;
}

#pragma mark - NSControlTextEditingDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
    NSTextField *textField = [obj object];
    NSScanner *scanner = [NSScanner scannerWithString:textField.stringValue];
    int i;
    BOOL isInteger = [scanner scanInt:&i] && i >= 0 && i < 256;
    if (textField == self.hexTextField) {
        NSColor *color = [self colorWithHexString:self.hexTextField.stringValue];
        if (color) {
            self.selectedColor = color;
        }
    } else if (textField == self.redTextField) {
        if (isInteger) {
            self.selectedColor = [NSColor cpk_colorWithRed:i / 255.0
                                                     green:_selectedColor.greenComponent
                                                      blue:_selectedColor.blueComponent
                                                     alpha:_selectedColor.alphaComponent];
        }
    } else if (textField == self.greenTextField) {
        if (isInteger) {
            self.selectedColor = [NSColor cpk_colorWithRed:_selectedColor.redComponent
                                                     green:i / 255.0
                                                      blue:_selectedColor.blueComponent
                                                     alpha:_selectedColor.alphaComponent];
        }
    } else if (textField == self.blueTextField) {
        if (isInteger) {
            self.selectedColor = [NSColor cpk_colorWithRed:_selectedColor.redComponent
                                                     green:_selectedColor.greenComponent
                                                      blue:i / 255.0
                                                     alpha:_selectedColor.alphaComponent];
        }
    } else if (self.alphaAllowed && textField == self.alphaTextField) {
        if (isInteger) {
            self.selectedColor = [NSColor cpk_colorWithRed:_selectedColor.redComponent
                                                     green:_selectedColor.greenComponent
                                                      blue:_selectedColor.blueComponent
                                                     alpha:i / 255.0];
        }
    }
}

- (NSColor *)colorWithHexString:(NSString *)hexString {
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    unsigned int value;
    if (![scanner scanHexInt:&value]) {
        return nil;
    }
    int r;
    int g;
    int b;
    if (hexString.length == 6) {
        r = (value >> 16) & 0xff;
        g = (value >> 8) & 0xff;
        b = (value >> 0) & 0xff;
    } else {
        return nil;
    }

    return [NSColor cpk_colorWithRed:r / 255.0
                               green:g / 255.0
                                blue:b / 255.0
                               alpha:_selectedColor.alphaComponent];
}

- (void)modeDidChange:(id)sender {
    switch ((CPKRGBViewMode) self.modeButton.selectedTag) {
        case kCPKRGBViewModeHSBWithHueSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeHue;
            self.gradientView.type = kCPKGradientViewTypeSaturationBrightness;
            break;
        case kCPKRGBViewModeHSBWithSaturationSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeSaturation;
            self.gradientView.type = kCPKGradientViewTypeBrightnessHue;
            break;
        case kCPKRGBViewModeHSBWithBrightnessSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeBrightness;
            self.gradientView.type = kCPKGradientViewTypeHueSaturation;
            break;
        case kCPKRGBViewModeRGBWithRedSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeRed;
            self.gradientView.type = kCPKGradientViewTypeGreenBlue;
            break;
        case kCPKRGBViewModeRGBWithGreenSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeGreen;
            self.gradientView.type = kCPKGradientViewTypeBlueRed;
            break;
        case kCPKRGBViewModeRGBWithBlueSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeBlue;
            self.gradientView.type = kCPKGradientViewTypeRedGreen;
            break;
    }
    self.gradientView.selectedColor = self.selectedColor;
    self.colorComponentSliderView.color = self.selectedColor;
}

@end
