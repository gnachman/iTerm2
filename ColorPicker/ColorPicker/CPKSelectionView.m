#import "CPKSelectionView.h"
#import "CPKColorComponentSliderView.h"
#import "CPKFlippedView.h"
#import "CPKGradientView.h"
#import "CPKAlphaSliderView.h"
#import "NSColor+CPK.h"
#import "NSObject+CPK.h"

static const CGFloat kLeftMargin = 8;
static const CGFloat kRightMargin = 8;
static const CGFloat kTopMargin = 8;
static const CGFloat kGradientHeight = 128;
static const CGFloat kMarginBetweenGradientAndColorComponentSlider = 8;
static const CGFloat kMarginBetweenPopupButtonAndGradient = 2;
static const CGFloat kColorComponentSliderHeight = 24;
static const CGFloat kAlphaSliderHeight = 12;
static const CGFloat kMarginBetweenTextFields = 4;
static const CGFloat kMarginBetweenLastSliderAndTextFields = 8;
static const CGFloat kColorTextFieldWidth = 32;
static const CGFloat kMarginBetweenTextFieldAndLabel = 0;
static const CGFloat kBottomMargin = 4;
static const CGFloat kMarginBetweenComponentSliders = 4;
static const CGFloat kMarginBetweenPopupButtonAndSliders = 2;
static const CGFloat kExtraRightMarginForTextFieldSwitch = 2;

static NSString *const kCPKSelectionViewShowHSBTextFieldsKey =
    @"kCPKSelectionViewShowHSBTextFieldsKey";

static NSString *const kCPKSelectionViewPreferredModeKey =
    @"kCPKSelectionViewPreferredModeKey";

typedef NS_ENUM(NSInteger, CPKRGBViewMode) {
    kCPKRGBViewModeHSBWithHueSliderTag,
    kCPKRGBViewModeHSBWithBrightnessSliderTag,
    kCPKRGBViewModeHSBWithSaturationSliderTag,

    kCPKRGBViewModeRGBWithRedSliderTag,
    kCPKRGBViewModeRGBWithGreenSliderTag,
    kCPKRGBViewModeRGBWithBlueSliderTag,

    kCPKRGBViewModeHSBSliders,
    kCPKRGBViewModeRGBSliders,
};

@interface CPKSelectionView() <NSTextFieldDelegate>
@property(nonatomic) NSPopUpButton *modeButton;
@property(nonatomic) CPKGradientView *gradientView;
@property(nonatomic) CPKColorComponentSliderView *colorComponentSliderView;

@property(nonatomic) CPKFlippedView *hsbSliders;
@property(nonatomic) CPKColorComponentSliderView *hueSliderView;
@property(nonatomic) CPKColorComponentSliderView *saturationSliderView;
@property(nonatomic) CPKColorComponentSliderView *brightnessSliderView;

@property(nonatomic) CPKFlippedView *rgbSliders;
@property(nonatomic) CPKColorComponentSliderView *redSliderView;
@property(nonatomic) CPKColorComponentSliderView *greenSliderView;
@property(nonatomic) CPKColorComponentSliderView *blueSliderView;

@property(nonatomic) CPKAlphaSliderView *alphaSliderView;
@property(nonatomic, copy) void (^block)(NSColor *);

@property(nonatomic) NSView *rgbTextFields;
@property(nonatomic) NSView *hsbTextFields;

@property(nonatomic) NSTextField *redTextField;
@property(nonatomic) NSTextField *greenTextField;
@property(nonatomic) NSTextField *blueTextField;

@property(nonatomic) NSTextField *hueTextField;
@property(nonatomic) NSTextField *saturationTextField;
@property(nonatomic) NSTextField *brightnessTextField;

@property(nonatomic) NSTextField *hexTextField;

// Slider labels
@property(nonatomic) NSTextField *hueLabel;
@property(nonatomic) NSTextField *saturationLabel;
@property(nonatomic) NSTextField *brightnessLabel;
@property(nonatomic) NSTextField *redLabel;
@property(nonatomic) NSTextField *greenLabel;
@property(nonatomic) NSTextField *blueLabel;

// Text field labels
@property(nonatomic) NSTextField *hueTextFieldLabel;
@property(nonatomic) NSTextField *saturationTextFieldLabel;
@property(nonatomic) NSTextField *brightnessTextFieldLabel;
@property(nonatomic) NSTextField *redTextFieldLabel;
@property(nonatomic) NSTextField *greenTextFieldLabel;
@property(nonatomic) NSTextField *blueTextFieldLabel;
@property(nonatomic) NSTextField *alphaTextFieldLabel;
@property(nonatomic) NSTextField *rgbHexTextFieldLabel;

@property(nonatomic) NSTextField *alphaTextField;

@property(nonatomic) NSButton *hslRgbTextFieldSwitch;

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

        [self createSubviews];

        self.block = block;
    }
    return self;
}

- (void)createSubviews {
    [self createModeButton];
    
    [self createSlidersWithColor:_selectedColor];
    
    __weak __typeof(self) weakSelf = self;
    self.gradientView =
    [[CPKGradientView alloc] initWithFrame:NSZeroRect
                                      type:kCPKGradientViewTypeSaturationBrightness
                                     block:^(NSColor *newColor) {
                                         [weakSelf setColorFromGradient:newColor];
                                     }];
    
    self.colorComponentSliderView =
        [[CPKColorComponentSliderView alloc] initWithFrame:NSZeroRect
                                                     color:_selectedColor
                                                      type:kCPKColorComponentSliderTypeHue
                                                     block:^(CGFloat newValue) {
                                                         [weakSelf setSliderValue:newValue];
                                                     }];
    
    if (_alphaAllowed) {
        self.alphaSliderView = [[CPKAlphaSliderView alloc] initWithFrame:NSZeroRect
                                                                   alpha:_selectedColor.alphaComponent
                                                                   color:_selectedColor
                                                                   block:^(CGFloat newAlpha) {
                                                                       [weakSelf setAlpha:newAlpha];
                                                                   }];
    }
    
    self.gradientView.selectedColor = _selectedColor;
    
    NSImage *rgbImage = [self cpk_imageNamed:@"RGB"];
    self.hslRgbTextFieldSwitch = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.hslRgbTextFieldSwitch.bordered = NO;
    self.hslRgbTextFieldSwitch.image = rgbImage;
    self.hslRgbTextFieldSwitch.imagePosition = NSImageOnly;
    self.hslRgbTextFieldSwitch.target = self;
    self.hslRgbTextFieldSwitch.action = @selector(toggleHslRgbTextFields:);
    self.hslRgbTextFieldSwitch.toolTip = @"Switch between RGB and HSB values.";
    
    [self createTextFieldsIncludingAlpha:_alphaAllowed];
    [self updateTextFieldsForColor:_selectedColor];
    
    self.subviews = @[ self.modeButton,
                       self.hsbSliders,
                       self.rgbSliders,
                       self.gradientView,
                       self.colorComponentSliderView,
                       self.hexTextField,
                       self.rgbTextFields,
                       self.hsbTextFields,
                       self.hslRgbTextFieldSwitch ];
    if (_alphaAllowed) {
        [self addSubview:self.alphaTextField];
        [self addSubview:self.alphaTextFieldLabel];
        [self addSubview:self.alphaSliderView];
    }
    [self addSubview:self.hexTextField];
    self.rgbHexTextFieldLabel = [self addLabel:@"RGB Hex" belowView:self.hexTextField toContainer:self];
    [self setTextFieldsRGB:![[NSUserDefaults standardUserDefaults] boolForKey:kCPKSelectionViewShowHSBTextFieldsKey]];
    // Update for the default mode
    [self modeDidChange:self.modeButton];
}

- (void)createModeButton {
    self.modeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
    [self.modeButton setTarget:self];
    [self.modeButton setAction:@selector(modeDidChange:)];
    
    [self.modeButton addItemWithTitle:@"HSB with Hue Slider"];
    [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeHSBWithHueSliderTag];
    [self.modeButton addItemWithTitle:@"HSB with Brightness Slider"];
    [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeHSBWithBrightnessSliderTag];
    [self.modeButton addItemWithTitle:@"HSB with Saturation Slider"];
    [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeHSBWithSaturationSliderTag];
    
    [self.modeButton.menu addItem:[NSMenuItem separatorItem]];
    
    [self.modeButton addItemWithTitle:@"RGB with Red Slider"];
    [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeRGBWithRedSliderTag];
    [self.modeButton addItemWithTitle:@"RGB with Green Slider"];
    [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeRGBWithGreenSliderTag];
    [self.modeButton addItemWithTitle:@"RGB with Blue Slider"];
    [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeRGBWithBlueSliderTag];
    
    [self.modeButton.menu addItem:[NSMenuItem separatorItem]];
    
    [self.modeButton addItemWithTitle:@"HSB Sliders"];
    [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeHSBSliders];
    [self.modeButton addItemWithTitle:@"RGB Sliders"];
    [self.modeButton.menu.itemArray.lastObject setTag:kCPKRGBViewModeRGBSliders];
    
    if ([[NSUserDefaults standardUserDefaults] objectForKey:kCPKSelectionViewPreferredModeKey]) {
        [self.modeButton selectItemWithTag:[[NSUserDefaults standardUserDefaults] integerForKey:kCPKSelectionViewPreferredModeKey]];
    }
}

- (void)createSlidersWithColor:(NSColor *)color {
    __weak __typeof(self) weakSelf = self;
    self.rgbSliders = [[CPKFlippedView alloc] initWithFrame:NSZeroRect];
    self.hsbSliders = [[CPKFlippedView alloc] initWithFrame:NSZeroRect];

    // Create HSB sliders
    self.hueSliderView =
        [[CPKColorComponentSliderView alloc] initWithFrame:NSZeroRect
                                                     color:color
                                                      type:kCPKColorComponentSliderTypeHue
                                                     block:^(CGFloat newValue) {
                                                         [weakSelf updateSelectedColorFromHSBSliders];
                                                     }];
    self.hueLabel = [self labelWithTitle:@"Hue" origin:NSZeroPoint];
    [self.hsbSliders addSubview:self.hueSliderView];
    [self.hsbSliders addSubview:self.hueLabel];

    self.saturationSliderView =
        [[CPKColorComponentSliderView alloc] initWithFrame:NSZeroRect
                                                     color:color
                                                      type:kCPKColorComponentSliderTypeSaturation
                                                     block:^(CGFloat newValue) {
                                                         [weakSelf updateSelectedColorFromHSBSliders];
                                                     }];
    self.saturationLabel = [self labelWithTitle:@"Saturation" origin:NSZeroPoint];
    [self.hsbSliders addSubview:self.saturationSliderView];
    [self.hsbSliders addSubview:self.saturationLabel];

    self.brightnessSliderView =
        [[CPKColorComponentSliderView alloc] initWithFrame:NSZeroRect
                                                     color:color
                                                      type:kCPKColorComponentSliderTypeBrightness
                                                     block:^(CGFloat newValue) {
                                                         [weakSelf updateSelectedColorFromHSBSliders];
                                                     }];
    self.brightnessLabel = [self labelWithTitle:@"Brightness" origin:NSZeroPoint];
    [self.hsbSliders addSubview:self.brightnessSliderView];
    [self.hsbSliders addSubview:self.brightnessLabel];


    // Create RGB sliders
    self.redSliderView =
        [[CPKColorComponentSliderView alloc] initWithFrame:NSZeroRect
                                                     color:color
                                                      type:kCPKColorComponentSliderTypeRed
                                                     block:^(CGFloat newValue) {
                                                         [weakSelf updateSelectedColorFromRGBSliders];

                                                     }];
    self.redLabel = [self labelWithTitle:@"Red" origin:NSZeroPoint];
    [self.rgbSliders addSubview:self.redSliderView];
    [self.rgbSliders addSubview:self.redLabel];

    self.greenSliderView =
        [[CPKColorComponentSliderView alloc] initWithFrame:NSZeroRect
                                                     color:color
                                                      type:kCPKColorComponentSliderTypeGreen
                                                     block:^(CGFloat newValue) {
                                                         [weakSelf updateSelectedColorFromRGBSliders];
                                                     }];
    self.greenLabel = [self labelWithTitle:@"Green" origin:NSZeroPoint];
    [self.rgbSliders addSubview:self.greenSliderView];
    [self.rgbSliders addSubview:self.greenLabel];

    self.blueSliderView =
        [[CPKColorComponentSliderView alloc] initWithFrame:NSZeroRect
                                                     color:color
                                                      type:kCPKColorComponentSliderTypeBlue
                                                     block:^(CGFloat newValue) {
                                                         [weakSelf updateSelectedColorFromRGBSliders];
                                                     }];
    self.blueLabel = [self labelWithTitle:@"Blue" origin:NSZeroPoint];
    [self.rgbSliders addSubview:self.blueSliderView];
    [self.rgbSliders addSubview:self.blueLabel];

    self.hsbSliders.hidden = YES;
    self.rgbSliders.hidden = YES;
}

- (void)createTextFieldsIncludingAlpha:(BOOL)alphaAllowed {
    // Create Alpha text field
    if (alphaAllowed) {
        self.alphaTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        self.alphaTextField.delegate = self;
    }
    
    // Create text field containers
    self.rgbTextFields = [[CPKFlippedView alloc] initWithFrame:NSZeroRect];
    self.hsbTextFields = [[CPKFlippedView alloc] initWithFrame:NSZeroRect];
    
    // Create HSB text fields
    self.brightnessTextField =[[NSTextField alloc] initWithFrame:NSZeroRect];
    self.brightnessTextField.delegate = self;

    self.saturationTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.saturationTextField.delegate = self;

    self.hueTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.hueTextField.delegate = self;

    // Create RGB text fields
    self.blueTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.blueTextField.delegate = self;

    self.greenTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.greenTextField.delegate = self;

    self.redTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.redTextField.delegate = self;

    self.hexTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    
    self.hexTextField.delegate = self;
    
    self.hsbTextFields.subviews = @[ self.hueTextField,
                                     self.brightnessTextField,
                                     self.saturationTextField ];
    self.rgbTextFields.subviews = @[ self.redTextField,
                                     self.greenTextField,
                                     self.blueTextField ];

    self.redTextFieldLabel = [self addLabel:@"R" belowView:self.redTextField toContainer:self.rgbTextFields];
    self.greenTextFieldLabel = [self addLabel:@"G" belowView:self.greenTextField toContainer:self.rgbTextFields];
    self.blueTextFieldLabel = [self addLabel:@"B" belowView:self.blueTextField toContainer:self.rgbTextFields];
    self.hueTextFieldLabel = [self addLabel:@"H" belowView:self.hueTextField toContainer:self.hsbTextFields];
    self.saturationTextFieldLabel = [self addLabel:@"S" belowView:self.saturationTextField toContainer:self.hsbTextFields];
    self.brightnessTextFieldLabel = [self addLabel:@"B" belowView:self.brightnessTextField toContainer:self.hsbTextFields];
    if (self.alphaAllowed) {
        self.alphaTextFieldLabel = [self addLabel:@"A" belowView:self.alphaTextField toContainer:self];
    }

    self.rgbTextFields.hidden = YES;
    self.hsbTextFields.hidden = NO;
}

- (void)layoutSubviews {
    NSRect frameRect = self.frame;
    NSRect frame;
    frame = NSMakeRect(kLeftMargin,
                       kTopMargin,
                       NSWidth(frameRect) - kRightMargin - kLeftMargin,
                       0);
    self.modeButton.frame = frame;
    [self.modeButton sizeToFit];
    frame = self.modeButton.frame;
    frame.size.width = NSWidth(frameRect) - kRightMargin - kLeftMargin;
    self.modeButton.frame = frame;
    
    frame = NSMakeRect(kLeftMargin,
                       NSMaxY(self.modeButton.frame) + kMarginBetweenPopupButtonAndGradient,
                       NSWidth(frameRect) - kRightMargin - kLeftMargin,
                       kGradientHeight);
    self.gradientView.frame = frame;
    
    frame = NSMakeRect(kLeftMargin,
                       NSMaxY(self.gradientView.frame) + kMarginBetweenGradientAndColorComponentSlider,
                       NSWidth(frameRect) - kRightMargin - kLeftMargin,
                       kColorComponentSliderHeight);
    
    self.colorComponentSliderView.frame = frame;

    [self layoutSliders];
    [self layoutTextFields];
}

- (void)layoutSliders {
    NSRect frameRect = self.frame;
    NSRect frame;
    const CGFloat labelHeight = NSHeight(self.redLabel.frame);
    frame = NSMakeRect(kLeftMargin,
                       NSMaxY(self.modeButton.frame) + kMarginBetweenPopupButtonAndSliders,
                       NSWidth(frameRect) - kRightMargin - kLeftMargin,
                       kColorComponentSliderHeight * 3 +
                           labelHeight * 3 +
                           kMarginBetweenComponentSliders * 2);
    self.rgbSliders.frame = frame;
    self.hsbSliders.frame = frame;

    // Lay out HSB sliders
    frame.size.height = kColorComponentSliderHeight;
    frame.origin = NSZeroPoint;
    self.hueSliderView.frame = frame;
    frame.origin.y += kColorComponentSliderHeight;
    frame.size.height = labelHeight;
    self.hueLabel.frame = frame;

    frame = NSMakeRect(0,
                       NSMaxY(frame) + kMarginBetweenComponentSliders,
                       NSWidth(frameRect) - kRightMargin - kLeftMargin,
                       kColorComponentSliderHeight);
    self.saturationSliderView.frame = frame;
    frame.origin.y += kColorComponentSliderHeight;
    frame.size.height = labelHeight;
    self.saturationLabel.frame = frame;

    frame = NSMakeRect(0,
                       NSMaxY(frame) + kMarginBetweenComponentSliders,
                       NSWidth(frameRect) - kRightMargin - kLeftMargin,
                       kColorComponentSliderHeight);
    self.brightnessSliderView.frame = frame;
    frame.origin.y += kColorComponentSliderHeight;
    frame.size.height = labelHeight;
    self.brightnessLabel.frame = frame;

    // Lay out RGB sliders
    frame = NSMakeRect(0,
                       0,
                       NSWidth(frameRect) - kRightMargin - kLeftMargin,
                       kColorComponentSliderHeight);
    self.redSliderView.frame = frame;
    frame.origin.y += kColorComponentSliderHeight;
    frame.size.height = labelHeight;
    self.redLabel.frame = frame;
    
    frame = NSMakeRect(0,
                       NSMaxY(frame) + kMarginBetweenComponentSliders,
                       NSWidth(frameRect) - kRightMargin - kLeftMargin,
                       kColorComponentSliderHeight);
    self.greenSliderView.frame = frame;
    frame.origin.y += kColorComponentSliderHeight;
    frame.size.height = labelHeight;
    self.greenLabel.frame = frame;

    frame = NSMakeRect(0,
                       NSMaxY(frame) + kMarginBetweenComponentSliders,
                       NSWidth(frameRect) - kRightMargin - kLeftMargin,
                       kColorComponentSliderHeight);
    self.blueSliderView.frame = frame;
    frame.origin.y += kColorComponentSliderHeight;
    frame.size.height = labelHeight;
    self.blueLabel.frame = frame;

    // Alpha
    if (self.alphaAllowed) {
        switch ((CPKRGBViewMode) self.modeButton.selectedTag) {
            case kCPKRGBViewModeHSBWithHueSliderTag:
            case kCPKRGBViewModeHSBWithSaturationSliderTag:
            case kCPKRGBViewModeHSBWithBrightnessSliderTag:
            case kCPKRGBViewModeRGBWithRedSliderTag:
            case kCPKRGBViewModeRGBWithGreenSliderTag:
            case kCPKRGBViewModeRGBWithBlueSliderTag:
                frame = NSMakeRect(kLeftMargin,
                                   NSMaxY(self.colorComponentSliderView.frame) + kMarginBetweenLastSliderAndTextFields,
                                   NSWidth(frameRect) - kRightMargin - kLeftMargin,
                                   kAlphaSliderHeight);
                break;

            case kCPKRGBViewModeHSBSliders:
            case kCPKRGBViewModeRGBSliders:
                frame = NSMakeRect(kLeftMargin,
                                   NSMaxY(self.rgbSliders.frame) + kMarginBetweenLastSliderAndTextFields,
                                   NSWidth(frameRect) - kRightMargin - kLeftMargin,
                                   kAlphaSliderHeight);
                break;
        }
        self.alphaSliderView.frame = frame;
    }
}

- (void)layoutLabel:(NSTextField *)label belowView:(NSView *)view {
    [label sizeToFit];
    label.frame = NSMakeRect(NSMinX(view.frame),
                             NSMaxY(view.frame) + kMarginBetweenTextFieldAndLabel,
                             NSWidth(view.frame),
                             NSHeight(label.frame));
}

- (void)layoutTextFields {
    CGFloat y;
    NSImage *rgbImage = [self cpk_imageNamed:@"RGB"];
    const CGFloat rightMargin = rgbImage.size.width;
    CGFloat x = NSMaxX(self.frame) - kRightMargin - rightMargin;
    if (self.alphaAllowed) {
        y = NSMaxY(self.alphaSliderView.frame) + kMarginBetweenLastSliderAndTextFields;
        self.alphaTextField.frame = NSMakeRect(x - kColorTextFieldWidth,
                                               y,
                                               kColorTextFieldWidth,
                                               0);
        [self layoutHeightOfTextField:self.alphaTextField];
        x -= self.alphaTextField.frame.size.width + kMarginBetweenTextFields;
    } else {
        switch ((CPKRGBViewMode) self.modeButton.selectedTag) {
            case kCPKRGBViewModeHSBWithHueSliderTag:
            case kCPKRGBViewModeHSBWithSaturationSliderTag:
            case kCPKRGBViewModeHSBWithBrightnessSliderTag:
            case kCPKRGBViewModeRGBWithRedSliderTag:
            case kCPKRGBViewModeRGBWithGreenSliderTag:
            case kCPKRGBViewModeRGBWithBlueSliderTag:
                y = NSMaxY(self.colorComponentSliderView.frame) + kMarginBetweenLastSliderAndTextFields;
                break;

            case kCPKRGBViewModeHSBSliders:
                y = NSMaxY(self.hsbSliders.frame) + kMarginBetweenLastSliderAndTextFields;
                break;

            case kCPKRGBViewModeRGBSliders:
                y = NSMaxY(self.rgbSliders.frame) + kMarginBetweenLastSliderAndTextFields;
                break;
        }
    }
    
    // Lay out text field containers
    const CGFloat textFieldsContainerWidth = kColorTextFieldWidth * 3 + kMarginBetweenTextFields * 2;
    self.rgbTextFields.frame = NSMakeRect(x - textFieldsContainerWidth,
                                          y,
                                          textFieldsContainerWidth,
                                          0);
    self.hsbTextFields.frame = self.rgbTextFields.frame;
    
    // Lay out HSB text fields
    x = textFieldsContainerWidth;
    self.brightnessTextField.frame = NSMakeRect(x - kColorTextFieldWidth,
                                                0,
                                                kColorTextFieldWidth,
                                                0);
    x -= self.brightnessTextField.frame.size.width + kMarginBetweenTextFields;

    self.saturationTextField.frame = NSMakeRect(x - kColorTextFieldWidth,
                                                0,
                                                kColorTextFieldWidth,
                                                0);
    x -= self.saturationTextField.frame.size.width + kMarginBetweenTextFields;

    self.hueTextField.frame = NSMakeRect(x - kColorTextFieldWidth,
                                         0,
                                         kColorTextFieldWidth,
                                         0);
    x -= self.hueTextField.frame.size.width + kMarginBetweenTextFields;

    // Lay out RGB text fields
    x = textFieldsContainerWidth;
    self.blueTextField.frame = NSMakeRect(x - kColorTextFieldWidth,
                                          0,
                                          kColorTextFieldWidth,
                                          0);
    x -= self.blueTextField.frame.size.width + kMarginBetweenTextFields;

    self.greenTextField.frame = NSMakeRect(x - kColorTextFieldWidth,
                                           0,
                                           kColorTextFieldWidth,
                                           0);
    x -= self.greenTextField.frame.size.width + kMarginBetweenTextFields;

    self.redTextField.frame = NSMakeRect(x - kColorTextFieldWidth,
                                         0,
                                         kColorTextFieldWidth,
                                         0);
    x -= self.redTextField.frame.size.width + kMarginBetweenTextFields;

    self.hexTextField.frame = NSMakeRect(kLeftMargin,
                                         y,
                                         NSMinX(self.rgbTextFields.frame) -
                                             kLeftMargin -
                                             kMarginBetweenTextFields,
                                         0);
    
    [self layoutHeightOfTextField:self.redTextField];
    [self layoutHeightOfTextField:self.greenTextField];
    [self layoutHeightOfTextField:self.blueTextField];

    [self layoutHeightOfTextField:self.hueTextField];
    [self layoutHeightOfTextField:self.saturationTextField];
    [self layoutHeightOfTextField:self.brightnessTextField];

    [self layoutHeightOfTextField:self.hexTextField];

    [self layoutLabel:self.rgbHexTextFieldLabel belowView:self.hexTextField];
    [self layoutLabel:self.redTextFieldLabel belowView:self.redTextField];
    [self layoutLabel:self.greenTextFieldLabel belowView:self.greenTextField];
    [self layoutLabel:self.blueTextFieldLabel belowView:self.blueTextField];
    [self layoutLabel:self.hueTextFieldLabel belowView:self.hueTextField];
    [self layoutLabel:self.saturationTextFieldLabel belowView:self.saturationTextField];
    [self layoutLabel:self.brightnessTextFieldLabel belowView:self.brightnessTextField];
    if (self.alphaAllowed) {
        [self layoutLabel:self.alphaTextFieldLabel belowView:self.alphaTextField];
    }

    NSRect frame = self.rgbTextFields.frame;
    frame.size.height = NSMaxY(self.redTextFieldLabel.frame);
    self.rgbTextFields.frame = frame;
    self.hsbTextFields.frame = frame;

    // Lay out rgb/hsb text field switch
    if (self.alphaAllowed) {
        y = NSMaxY(self.alphaSliderView.frame) + kMarginBetweenLastSliderAndTextFields;
    } else {
        switch ((CPKRGBViewMode) self.modeButton.selectedTag) {
            case kCPKRGBViewModeHSBWithHueSliderTag:
            case kCPKRGBViewModeHSBWithSaturationSliderTag:
            case kCPKRGBViewModeHSBWithBrightnessSliderTag:
            case kCPKRGBViewModeRGBWithRedSliderTag:
            case kCPKRGBViewModeRGBWithGreenSliderTag:
            case kCPKRGBViewModeRGBWithBlueSliderTag:
                y = NSMaxY(self.colorComponentSliderView.frame) + kMarginBetweenLastSliderAndTextFields;
                break;

            case kCPKRGBViewModeHSBSliders:
            case kCPKRGBViewModeRGBSliders:
                y = NSMaxY(self.rgbSliders.frame) + kMarginBetweenLastSliderAndTextFields;
                break;
        }
    }

    frame = NSMakeRect(NSMaxX(self.frame) -
                           rgbImage.size.width -
                           kRightMargin + kMarginBetweenTextFields -
                           kExtraRightMarginForTextFieldSwitch,
                       y,
                       rgbImage.size.width,
                       rgbImage.size.height);
    self.hslRgbTextFieldSwitch.frame = frame;
}

- (void)layoutHeightOfTextField:(NSTextField *)textField {
    NSRect frame = textField.frame;
    [textField sizeToFit];
    frame.size.height = textField.frame.size.height;
    textField.frame = frame;
}

- (void)setTextFieldsRGB:(BOOL)rgb {
    [[NSUserDefaults standardUserDefaults] setBool:!rgb
                                            forKey:kCPKSelectionViewShowHSBTextFieldsKey];
    NSImage *image = [self cpk_imageNamed:rgb ? @"HSB" : @"RGB"];
    self.hslRgbTextFieldSwitch.image = image;
    self.rgbTextFields.hidden = !rgb;
    self.hsbTextFields.hidden = rgb;
}

- (void)toggleHslRgbTextFields:(id)sender {
    [self setTextFieldsRGB:self.rgbTextFields.hidden];
}

- (NSTextField *)labelWithTitle:(NSString *)string origin:(NSPoint)origin {
    NSTextField *label =
        [[NSTextField alloc] initWithFrame:NSMakeRect(origin.x,
                                                      origin.y,
                                                      0,
                                                      0)];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.stringValue = string;
    [label sizeToFit];
    return label;
}

- (NSTextField *)addLabel:(NSString *)string
                belowView:(NSView *)view
              toContainer:(NSView *)container {
    NSTextField *label = [self labelWithTitle:string origin:NSZeroPoint];
    [self layoutLabel:label belowView:view];
    label.alignment = NSCenterTextAlignment;
    [container addSubview:label];
    return label;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)updateSelectedColorFromHSBSliders {
    self.selectedColor = [NSColor cpk_colorWithHue:self.hueSliderView.selectedValue
                                        saturation:self.saturationSliderView.selectedValue
                                        brightness:self.brightnessSliderView.selectedValue
                                             alpha:self.selectedColor.alphaComponent];
    [self updateSliderGradients];
}

- (void)updateSliderGradients {
    [self.hueSliderView setGradientColor:[NSColor cpk_colorWithHue:0
                                                        saturation:self.saturationSliderView.selectedValue
                                                        brightness:self.brightnessSliderView.selectedValue
                                                             alpha:1]];
    [self.saturationSliderView setGradientColor:[NSColor cpk_colorWithHue:self.hueSliderView.selectedValue
                                                               saturation:1
                                                               brightness:self.brightnessSliderView.selectedValue
                                                                    alpha:1]];
    [self.brightnessSliderView setGradientColor:[NSColor cpk_colorWithHue:self.hueSliderView.selectedValue
                                                               saturation:self.saturationSliderView.selectedValue
                                                               brightness:1
                                                                    alpha:1]];

    [self.redSliderView setGradientColor:[NSColor cpk_colorWithRed:0
                                                             green:self.greenSliderView.selectedValue
                                                              blue:self.blueSliderView.selectedValue
                                                             alpha:1]];
    [self.greenSliderView setGradientColor:[NSColor cpk_colorWithRed:self.redSliderView.selectedValue
                                                             green:0
                                                              blue:self.blueSliderView.selectedValue
                                                             alpha:1]];
    [self.blueSliderView setGradientColor:[NSColor cpk_colorWithRed:self.redSliderView.selectedValue
                                                             green:self.greenSliderView.selectedValue
                                                              blue:0
                                                             alpha:1]];
}

- (void)updateSelectedColorFromRGBSliders {
    self.selectedColor = [NSColor cpk_colorWithRed:self.redSliderView.selectedValue
                                             green:self.greenSliderView.selectedValue
                                              blue:self.blueSliderView.selectedValue
                                             alpha:self.selectedColor.alphaComponent];
    [self updateSliderGradients];
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

    self.redSliderView.color = selectedColor;
    self.greenSliderView.color = selectedColor;
    self.blueSliderView.color = selectedColor;

    self.hueSliderView.color = selectedColor;
    self.saturationSliderView.color = selectedColor;
    self.brightnessSliderView.color = selectedColor;

    dispatch_async(dispatch_get_main_queue(), ^{
        [_gradientView setNeedsDisplay:YES];
    });
    [self updateTextFieldsForColor:self.selectedColor];
    self.block(selectedColor);
}

- (void)updateTextFieldsForColor:(NSColor *)color {
    self.hexTextField.stringValue = [NSString stringWithFormat:@"%02x%02x%02x",
                                        (int)round(color.redComponent * 255),
                                        (int)round(color.greenComponent * 255),
                                        (int)round(color.blueComponent * 255)];
    self.redTextField.stringValue =
        [NSString stringWithFormat:@"%d", (int)round(color.redComponent * 255)];
    self.greenTextField.stringValue =
        [NSString stringWithFormat:@"%d", (int)round(color.greenComponent * 255)];
    self.blueTextField.stringValue =
        [NSString stringWithFormat:@"%d", (int)round(color.blueComponent * 255)];

    self.hueTextField.stringValue =
        [NSString stringWithFormat:@"%d", (int)round(color.hueComponent * 255)];
    self.saturationTextField.stringValue =
        [NSString stringWithFormat:@"%d", (int)round(color.saturationComponent * 255)];
    self.brightnessTextField.stringValue =
        [NSString stringWithFormat:@"%d", (int)round(color.brightnessComponent * 255)];
    
    if (self.alphaAllowed) {
        self.alphaTextField.stringValue =
            [NSString stringWithFormat:@"%d",(int)round(color.alphaComponent * 255)];
    }
}

- (void)sizeToFit {
    [self layoutSubviews];
    NSRect frame = NSMakeRect(NSMinX(self.frame),
                              NSMinY(self.frame),
                              NSWidth(self.bounds),
                              [self desiredHeight]);
    self.frame = frame;
}

- (CGFloat)desiredHeight {
    return NSMaxY(self.rgbTextFields.frame) + kBottomMargin;
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
    } else if (textField == self.hueTextField) {
        if (isInteger) {
            self.selectedColor = [NSColor cpk_colorWithHue:i / 255.0
                                                saturation:_selectedColor.saturationComponent
                                                brightness:_selectedColor.brightnessComponent
                                                     alpha:_selectedColor.alphaComponent];
        }
    } else if (textField == self.saturationTextField) {
        if (isInteger) {
            self.selectedColor = [NSColor cpk_colorWithHue:_selectedColor.hueComponent
                                                saturation:i / 255.0
                                                brightness:_selectedColor.brightnessComponent
                                                     alpha:_selectedColor.alphaComponent];
        }
    } else if (textField == self.brightnessTextField) {
        if (isInteger) {
            self.selectedColor = [NSColor cpk_colorWithHue:_selectedColor.hueComponent
                                                saturation:_selectedColor.saturationComponent
                                                brightness:i / 255.0
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

- (void)showGradientAndColorComponentSlider {
    self.rgbSliders.hidden = YES;
    self.hsbSliders.hidden = YES;
    self.gradientView.hidden = NO;
    self.colorComponentSliderView.hidden = NO;
}

- (void)modeDidChange:(id)sender {
    [[NSUserDefaults standardUserDefaults] setInteger:self.modeButton.selectedTag
                                               forKey:kCPKSelectionViewPreferredModeKey];
    
    switch ((CPKRGBViewMode) self.modeButton.selectedTag) {
        case kCPKRGBViewModeHSBWithHueSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeHue;
            self.gradientView.type = kCPKGradientViewTypeSaturationBrightness;
            [self showGradientAndColorComponentSlider];
            break;
        case kCPKRGBViewModeHSBWithSaturationSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeSaturation;
            self.gradientView.type = kCPKGradientViewTypeBrightnessHue;
            [self showGradientAndColorComponentSlider];
            break;
        case kCPKRGBViewModeHSBWithBrightnessSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeBrightness;
            self.gradientView.type = kCPKGradientViewTypeHueSaturation;
            [self showGradientAndColorComponentSlider];
            break;
        case kCPKRGBViewModeRGBWithRedSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeRed;
            self.gradientView.type = kCPKGradientViewTypeGreenBlue;
            [self showGradientAndColorComponentSlider];
            break;
        case kCPKRGBViewModeRGBWithGreenSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeGreen;
            self.gradientView.type = kCPKGradientViewTypeBlueRed;
            [self showGradientAndColorComponentSlider];
            break;
        case kCPKRGBViewModeRGBWithBlueSliderTag:
            self.colorComponentSliderView.type = kCPKColorComponentSliderTypeBlue;
            self.gradientView.type = kCPKGradientViewTypeRedGreen;
            [self showGradientAndColorComponentSlider];
            break;
        case kCPKRGBViewModeHSBSliders:
            self.hueSliderView.selectedValue = self.selectedColor.hueComponent;
            self.saturationSliderView.selectedValue = self.selectedColor.saturationComponent;
            self.brightnessSliderView.selectedValue = self.selectedColor.brightnessComponent;

            self.rgbSliders.hidden = YES;
            self.hsbSliders.hidden = NO;

            self.gradientView.hidden = YES;
            self.colorComponentSliderView.hidden = YES;

            [self updateSliderGradients];
            break;
        case kCPKRGBViewModeRGBSliders:
            self.redSliderView.selectedValue = self.selectedColor.redComponent;
            self.greenSliderView.selectedValue = self.selectedColor.greenComponent;
            self.blueSliderView.selectedValue = self.selectedColor.blueComponent;

            self.rgbSliders.hidden = NO;
            self.hsbSliders.hidden = YES;

            self.gradientView.hidden = YES;
            self.colorComponentSliderView.hidden = YES;

            [self updateSliderGradients];
            break;
    }
    self.gradientView.selectedColor = self.selectedColor;
    self.colorComponentSliderView.color = self.selectedColor;
    [self setNeedsDisplay:YES];

    [self layoutSubviews];
    [self.delegate selectionViewContentSizeDidChange];
}

@end
