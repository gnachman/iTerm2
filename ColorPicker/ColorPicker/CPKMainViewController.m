#import "CPKMainViewController.h"

#import "CPKColor.h"
#import "CPKColorNamer.h"
#import "CPKControlsView.h"
#import "CPKEyedropperWindow.h"
#import "CPKFavorite.h"
#import "CPKFavoritesView.h"
#import "CPKFlippedView.h"
#import "CPKLogging.h"
#import "CPKSelectionView.h"
#import "NSColor+CPK.h"

static CGFloat kDesiredWidth(void) {
    if (@available(macOS 26, *)) {
        return 307;
    }
    return 292;
}

static CGFloat kDesiredHeight(void) {
    if (@available(macOS 26, *)) {
        return 393;
    }
    return 387;
}

static const CGFloat kLeftMargin = 8;
static const CGFloat kRightMargin = 8;
static const CGFloat kBottomMargin = 8;

@interface CPKMainViewController ()<CPKSelectionViewDelegate>
@property(nonatomic, copy) void (^block)(NSColor *);
@property(nonatomic, copy) void (^useSystemColorPickerBlock)(void);
@property(nonatomic) NSColor *selectedColor;
@property(nonatomic) CGFloat desiredHeight;
@property(nonatomic) CPKSelectionView *selectionView;
@property(nonatomic) CPKControlsView *controlsView;
@property(nonatomic) CPKFavoritesView *favoritesView;
@property(nonatomic) BOOL alphaAllowed;
@property(nonatomic) BOOL noColorAllowed;
@end

@implementation CPKMainViewController

- (instancetype)initWithBlock:(void (^)(NSColor *))block
         useSystemColorPicker:(void (^)(void))useSystemColorPickerBlock
                        color:(NSColor *)color
                      options:(CPKMainViewControllerOptions)options
                   colorSpace:(NSColorSpace *)colorSpace {
    NSAssert(colorSpace != nil, @"colorSpace must not be nil");
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _block = [block copy];
        _colorSpace = colorSpace;
        _useSystemColorPickerBlock = [useSystemColorPickerBlock copy];
        if (!color) {
            color = [NSColor cpk_colorWithRed:0 green:0 blue:0 alpha:0 colorSpace:colorSpace];
        }
        BOOL alphaAllowed = !!(options & CPKMainViewControllerOptionsAlpha);
        BOOL noColorAllowed = !!(options & CPKMainViewControllerOptionsNoColor);
        if (!alphaAllowed) {
            color = [color colorWithAlphaComponent:1];
        }
        color = [color colorUsingColorSpace:self.colorSpace];
        _selectedColor = color;
        self.alphaAllowed = alphaAllowed;
        self.noColorAllowed = noColorAllowed;
    }
    return self;
}

- (void)loadView {
    // The 100 value below is temporary and will be changed before we return to the correct height.
    self.view = [[CPKFlippedView alloc] initWithFrame:NSMakeRect(0,
                                                                 0,
                                                                 kDesiredWidth(),
                                                                 100)];
    self.view.autoresizesSubviews = NO;

    __weak __typeof(self) weakSelf = self;
    NSAssert(self.colorSpace != nil, @"colorSpace is nil when creating selectionView in loadView");
    self.selectionView = [[CPKSelectionView alloc] initWithFrame:self.view.bounds
                                                           block: ^(CPKColor *color) {
                                                               [weakSelf selectColor:color.color
                                                                 updateSelectionView:NO];
                                                           }
                                                           color:[[CPKColor alloc] initWithColor:_selectedColor]
                                                      colorSpace:self.colorSpace
                                                    alphaAllowed:self.alphaAllowed];
    self.selectionView.delegate = self;
    self.selectionView.colorSpaceDidChangeBlock = ^(NSColorSpace *newColorSpace) {
        NSCAssert(newColorSpace != nil, @"colorSpaceDidChangeBlock received nil colorSpace");
        weakSelf.colorSpace = newColorSpace;
        if (weakSelf.colorSpaceDidChangeBlock) {
            weakSelf.colorSpaceDidChangeBlock(newColorSpace);
        }
    };
    [self.selectionView sizeToFit];

    self.controlsView =
        [[CPKControlsView alloc] initWithFrame:NSMakeRect(0,
                                                          NSMaxY(self.selectionView.frame),
                                                          kDesiredWidth(),
                                                          [CPKControlsView desiredHeight])
                                noColorAllowed:self.noColorAllowed];
    self.controlsView.swatchColor = _selectedColor;
    self.controlsView.addFavoriteBlock = ^() {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Name this color";
        alert.informativeText = @"Enter a name for this new saved color:";
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];

        NSTextField *input =
            [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
        input.stringValue = [[CPKColorNamer sharedInstance] nameForColor:weakSelf.selectedColor];
        alert.accessoryView = input;
        [alert layout];
        [[alert window] makeFirstResponder:input];
        NSInteger button = [alert runModal];
        if (button == NSAlertFirstButtonReturn) {
            [weakSelf.favoritesView addFavorite:[CPKFavorite favoriteWithColor:weakSelf.selectedColor
                                                                          name:input.stringValue]];
        }
    };
    self.controlsView.selectNoColorBlock = ^() {
        weakSelf.selectionView.selectedColor = nil;
    };
    self.controlsView.removeFavoriteBlock = ^() {
        [weakSelf.favoritesView removeSelectedFavorites];
    };
    self.controlsView.startPickingBlock = ^() {
        [CPKEyedropperWindow pickColorWithCompletion:^(NSColor *color, NSColorSpace *colorSpace) {
            if (color) {
                // Adopt the colorspace from the eyedropper if available
                if (colorSpace) {
                    weakSelf.colorSpace = colorSpace;
                }
                weakSelf.selectionView.selectedColor = [[CPKColor alloc] initWithColor:color];
            }
        }];
    };
    self.controlsView.useNativeColorPicker = ^() {
        if (weakSelf.useSystemColorPickerBlock) {
            weakSelf.useSystemColorPickerBlock();
        }
    };
    self.favoritesView =
        [[CPKFavoritesView alloc] initWithFrame:NSMakeRect(kLeftMargin,
                                                           NSMaxY(self.controlsView.frame),
                                                           kDesiredWidth() - kLeftMargin - kRightMargin,
                                                           [self favoritesViewHeight])
                                     colorSpace:self.colorSpace];
    self.favoritesView.selectionDidChangeBlock = ^(NSColor *newColor) {
        if (newColor) {
            weakSelf.selectionView.selectedColor = [[CPKColor alloc] initWithColor:newColor];
            [weakSelf setColorSpace:newColor.colorSpace];
            weakSelf.controlsView.removeEnabled = YES;
        } else {
            weakSelf.controlsView.removeEnabled = NO;
        }
    };

    self.desiredHeight = NSMaxY(self.favoritesView.frame) + kBottomMargin;

    self.view.subviews = @[ self.selectionView,
                            self.controlsView,
                            self.favoritesView ];

    self.view.frame = NSMakeRect(0, 0, kDesiredWidth(), self.desiredHeight);
}

- (NSSize)desiredSize {
    [self view];
    return NSMakeSize(kDesiredWidth(), self.desiredHeight);
}

- (CGFloat)favoritesViewHeight {
    return kDesiredHeight() - NSMaxY(self.controlsView.frame);
}

- (void)viewDidAppear {
    self.controlsView.useSystemColorPicker =
        [[NSUserDefaults standardUserDefaults] boolForKey:kCPKUseSystemColorPicker];
}

- (void)selectColor:(NSColor *)color {
    CPKLog(@"CPKMainViewController.selectColor(%@)", color);
    [self selectColor:color updateSelectionView:YES];
}

- (void)selectColor:(NSColor *)color updateSelectionView:(BOOL)updateSelectionView {
    CPKLog(@"CPKMainViewController.selectColor(%@, updateSelectionView:%@)", color, @(updateSelectionView));
    self.selectedColor = color;
    self.controlsView.swatchColor = color;
    _block(color);
    [self.favoritesView selectColor:color];
    if (updateSelectionView) {
        [self.selectionView setSelectedColor:[[CPKColor alloc] initWithColor:color]];
    }
}

- (void)setColorSpace:(NSColorSpace *)colorSpace {
    NSAssert(colorSpace != nil, @"setColorSpace: called with nil colorSpace");
    if ([_colorSpace isEqual:colorSpace]) {
        return;
    }
    _colorSpace = colorSpace;
    if (self.selectionView) {
        self.selectionView.colorSpace = colorSpace;
    }
    if (self.favoritesView) {
        self.favoritesView.colorSpace = colorSpace;
    }
}

#pragma mark - CPKSelectionViewDelegate

- (void)selectionViewContentSizeDidChange {
    [self.selectionView sizeToFit];
    self.controlsView.frame = NSMakeRect(0,
                                         NSMaxY(self.selectionView.frame),
                                         kDesiredWidth(),
                                         [CPKControlsView desiredHeight]);

    self.favoritesView.frame = NSMakeRect(kLeftMargin,
                                          NSMaxY(self.controlsView.frame),
                                          kDesiredWidth() - kLeftMargin - kRightMargin,
                                          [self favoritesViewHeight]);
}

@end
