#import "CPKControlsView.h"
#import "CPKSwatchView.h"
#import "NSObject+CPK.h"

static const CGFloat kMarginBetweenButtons = 0;
static const CGFloat kMarginBetweenButtonsAndSwatch = 8;
static const CGFloat kLeftMargin = 8;
static const CGFloat kRightMargin = 8;
static const CGFloat kTopMargin = 0;
static const CGFloat kBottomMargin = 8;
NSString *const kCPKUseSystemColorPicker = @"kCPKUseSystemColorPicker";

@interface CPKControlsView()
@property(nonatomic) NSButton *noColor;
@property(nonatomic) NSButton *addFavorite;
@property(nonatomic) NSButton *removeFavorite;
@property(nonatomic) NSButton *eyedropperMode;
@property(nonatomic) NSButton *escapeHatch;
@property(nonatomic) CPKSwatchView *swatch;
@end

@implementation CPKControlsView

- (instancetype)initWithFrame:(NSRect)frameRect {
    return [self initWithFrame:frameRect noColorAllowed:NO];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect noColorAllowed:(BOOL)noColorAllowed {
    self = [super initWithFrame:frameRect];
    if (self) {
        CGFloat x = kLeftMargin;
        if (noColorAllowed) {
            self.noColor = [self addButtonWithImage:[self cpk_imageNamed:@"NoColor"]
                                             origin:NSMakePoint(x, kTopMargin)];
            self.noColor.toolTip = @"Select the absence of color";
            [self.noColor setTarget:self];
            [self.noColor setAction:@selector(selectNoColor:)];
            x = NSMaxX(self.noColor.frame) + kMarginBetweenButtons;
        }

        self.addFavorite = [self addButtonWithImage:[self cpk_imageNamed:@"Add"]
                                             origin:NSMakePoint(x, kTopMargin)];
        self.addFavorite.toolTip = @"Save color as a Favorite";
        [self.addFavorite setTarget:self];
        [self.addFavorite setAction:@selector(addFavorite:)];

        NSPoint origin = NSMakePoint(NSMaxX(self.addFavorite.frame) + kMarginBetweenButtons,
                                     kTopMargin);
        self.removeFavorite = [self addButtonWithImage:[self cpk_imageNamed:@"Remove"]
                                                origin:origin];
        self.removeFavorite.toolTip = @"Remove selected Favorite color";
        [self.removeFavorite setTarget:self];
        [self.removeFavorite setAction:@selector(removeFavorite:)];
        self.removeEnabled = NO;

        origin = NSMakePoint(NSMaxX(self.removeFavorite.frame) + kMarginBetweenButtons,
                             kTopMargin);
        self.eyedropperMode = [self addButtonWithImage:[self cpk_imageNamed:@"Eyedropper"]
                                                origin:origin];
        self.eyedropperMode.toolTip = @"Open the eye dropper";
        [self.eyedropperMode setTarget:self];
        [self.eyedropperMode setAction:@selector(eyedropperMode:)];

        origin = NSMakePoint(NSMaxX(self.eyedropperMode.frame) + kMarginBetweenButtons,
                             kTopMargin);
        self.escapeHatch = [self addButtonWithImage:[self cpk_imageNamed:@"EscapeHatch"]
                                             origin:origin];
        self.escapeHatch.toolTip = @"Use the system color picker";
        [self.escapeHatch setTarget:self];
        [self.escapeHatch setAction:@selector(escapeHatch:)];

        origin = NSMakePoint(NSMaxX(self.escapeHatch.frame) + kMarginBetweenButtonsAndSwatch,
                             kTopMargin);
        self.swatch =
            [[CPKSwatchView alloc] initWithFrame:NSMakeRect(NSMaxX(self.escapeHatch.frame) +
                                                                kMarginBetweenButtonsAndSwatch,
                                                            kTopMargin,
                                                            NSWidth(frameRect) -
                                                                NSMaxX(self.escapeHatch.frame) -
                                                                kMarginBetweenButtonsAndSwatch -
                                                                kRightMargin,
                                                            NSHeight(self.addFavorite.frame))];
        [self addSubview:self.swatch];
    }
    return self;
}

- (NSButton *)addButtonWithImage:(NSImage *)image origin:(NSPoint)origin {
    assert(image);
    NSRect frame;
    frame.origin = origin;
    frame.size = image.size;
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.bordered = NO;
    button.image = image;
    button.imagePosition = NSImageOnly;
    [self addSubview:button];
    return button;
}

- (void)setRemoveEnabled:(BOOL)removeEnabled {
    self.removeFavorite.enabled = removeEnabled;
}

+ (CGFloat)desiredHeight {
    return [self cpk_imageNamed:@"Add"].size.height + kTopMargin + kBottomMargin;
}

- (void)setSwatchColor:(NSColor *)color {
    self.swatch.color = color;
    [self.swatch setNeedsDisplay:YES];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)colorPanelDidClose {
  self.useSystemColorPicker = NO;
}

- (void)setUseSystemColorPicker:(BOOL)useSystemColorPicker {
    if (useSystemColorPicker == _useSystemColorPicker) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setBool:useSystemColorPicker
                                            forKey:kCPKUseSystemColorPicker];
    _useSystemColorPicker = useSystemColorPicker;
    self.escapeHatch.image =
        self.useSystemColorPicker ? [self cpk_imageNamed:@"ActiveEscapeHatch"] :
                                    [self cpk_imageNamed:@"EscapeHatch"];
    if (_useNativeColorPicker) {
        __weak __typeof(self) weakSelf = self;
        weakSelf.useNativeColorPicker(useSystemColorPicker);
    }
}

#pragma mark - Actions

- (void)selectNoColor:(id)sender {
    self.selectNoColorBlock();
}

- (void)addFavorite:(id)sender {
    if (_addFavoriteBlock) {
        _addFavoriteBlock();
    }
}

- (void)removeFavorite:(id)sender {
    if (_removeFavoriteBlock) {
        _removeFavoriteBlock();
    }
}

- (void)eyedropperMode:(id)sender {
    if (_startPickingBlock) {
        self.eyedropperMode.image = [self cpk_imageNamed:@"ActiveEyedropper"];
        dispatch_async(dispatch_get_main_queue(), ^{
            _startPickingBlock();
            self.eyedropperMode.image = [self cpk_imageNamed:@"Eyedropper"];
        });
    }
}

- (void)escapeHatch:(id)sender {
    self.useSystemColorPicker = !self.useSystemColorPicker;
}

@end
