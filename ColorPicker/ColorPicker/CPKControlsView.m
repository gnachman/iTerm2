#import "CPKControlsView.h"
#import "CPKSwatchView.h"
#import "NSObject+CPK.h"

static const CGFloat kMarginBetweenButtons = 0;
static const CGFloat kMarginBetweenButtonsAndSwatch = 8;
static const CGFloat kLeftMargin = 8;
static const CGFloat kRightMargin = 8;
static const CGFloat kTopMargin = 0;
static const CGFloat kBottomMargin = 8;

@interface CPKControlsView()
@property(nonatomic) NSButton *addFavorite;
@property(nonatomic) NSButton *removeFavorite;
@property(nonatomic) NSButton *eyedropperMode;
@property(nonatomic) CPKSwatchView *swatch;
@end

@implementation CPKControlsView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.addFavorite = [self addButtonWithImage:[self cpk_imageNamed:@"Add"]
                                             origin:NSMakePoint(kLeftMargin, kTopMargin)];
        [self.addFavorite setTarget:self];
        [self.addFavorite setAction:@selector(addFavorite:)];

        NSPoint origin = NSMakePoint(NSMaxX(self.addFavorite.frame) + kMarginBetweenButtons,
                                     kTopMargin);
        self.removeFavorite = [self addButtonWithImage:[self cpk_imageNamed:@"Remove"]
                                                origin:origin];
        [self.removeFavorite setTarget:self];
        [self.removeFavorite setAction:@selector(removeFavorite:)];
        self.removeEnabled = NO;

        origin = NSMakePoint(NSMaxX(self.removeFavorite.frame) + kMarginBetweenButtons,
                             kTopMargin);
        self.eyedropperMode = [self addButtonWithImage:[self cpk_imageNamed:@"Eyedropper"]
                                                origin:origin];
        [self.eyedropperMode setTarget:self];
        [self.eyedropperMode setAction:@selector(eyedropperMode:)];

        origin = NSMakePoint(NSMaxX(self.eyedropperMode.frame) + kMarginBetweenButtonsAndSwatch,
                             kTopMargin);
        self.swatch =
            [[CPKSwatchView alloc] initWithFrame:NSMakeRect(NSMaxX(self.eyedropperMode.frame) +
                                                                kMarginBetweenButtonsAndSwatch,
                                                            kTopMargin,
                                                            NSWidth(frameRect) -
                                                                NSMaxX(self.eyedropperMode.frame) -
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

#pragma mark - Actions

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

@end
