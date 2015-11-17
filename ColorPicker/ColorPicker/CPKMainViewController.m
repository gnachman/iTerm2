#import "CPKMainViewController.h"
#import "CPKColorNamer.h"
#import "CPKControlsView.h"
#import "CPKEyedropperWindow.h"
#import "CPKFavorite.h"
#import "CPKFavoritesView.h"
#import "CPKFlippedView.h"
#import "CPKSelectionView.h"
#import "NSColor+CPK.h"

static const CGFloat kDesiredWidth = 272;
static const CGFloat kDesiredHeight = 387;

static const CGFloat kLeftMargin = 8;
static const CGFloat kRightMargin = 8;
static const CGFloat kBottomMargin = 8;

@interface CPKMainViewController ()<CPKSelectionViewDelegate>
@property(nonatomic, copy) void (^block)(NSColor *);
@property(nonatomic, copy) void (^useSystemColorPickerBlock)();
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
                        color:(NSColor *)color
                 alphaAllowed:(BOOL)alphaAllowed {
    CPKMainViewControllerOptions options = 0;
    if (alphaAllowed) {
        options |= CPKMainViewControllerOptionsAlpha;
    }
    return [self initWithBlock:block useSystemColorPicker:nil color:color options:options];
}

- (instancetype)initWithBlock:(void (^)(NSColor *))block
         useSystemColorPicker:(void (^)())useSystemColorPickerBlock
                        color:(NSColor *)color
                      options:(CPKMainViewControllerOptions)options {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _block = [block copy];
        _useSystemColorPickerBlock = [useSystemColorPickerBlock copy];
        if (!color) {
            color = [NSColor cpk_colorWithRed:0 green:0 blue:0 alpha:0];
        }
        BOOL alphaAllowed = !!(options & CPKMainViewControllerOptionsAlpha);
        BOOL noColorAllowed = !!(options & CPKMainViewControllerOptionsNoColor);
        if (!alphaAllowed) {
            color = [color colorWithAlphaComponent:1];
        }
        color = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
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
                                                                 kDesiredWidth,
                                                                 100)];
    self.view.autoresizesSubviews = NO;

    __weak __typeof(self) weakSelf = self;
    self.selectionView = [[CPKSelectionView alloc] initWithFrame:self.view.bounds
                                                           block: ^(NSColor *color) {
                                                               [weakSelf selectColor:color];
                                                           }
                                                           color:_selectedColor
                                                    alphaAllowed:self.alphaAllowed];
    self.selectionView.delegate = self;
    [self.selectionView sizeToFit];

    self.controlsView =
        [[CPKControlsView alloc] initWithFrame:NSMakeRect(0,
                                                          NSMaxY(self.selectionView.frame),
                                                          kDesiredWidth,
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
        NSColor *color = [CPKEyedropperWindow pickColor];
        if (color) {
            weakSelf.selectionView.selectedColor = color;
        }
    };
    self.controlsView.useNativeColorPicker = ^() {
        if (weakSelf.useSystemColorPickerBlock) {
            weakSelf.useSystemColorPickerBlock();
        }
    };
    self.favoritesView =
        [[CPKFavoritesView alloc] initWithFrame:NSMakeRect(kLeftMargin,
                                                           NSMaxY(self.controlsView.frame),
                                                           kDesiredWidth - kLeftMargin - kRightMargin,
                                                           [self favoritesViewHeight])];
    self.favoritesView.selectionDidChangeBlock = ^(NSColor *newColor) {
        if (newColor) {
            weakSelf.selectionView.selectedColor = newColor;
            weakSelf.controlsView.removeEnabled = YES;
        } else {
            weakSelf.controlsView.removeEnabled = NO;
        }
    };

    self.desiredHeight = NSMaxY(self.favoritesView.frame) + kBottomMargin;

    self.view.subviews = @[ self.selectionView,
                            self.controlsView,
                            self.favoritesView ];

    self.view.frame = NSMakeRect(0, 0, kDesiredWidth, self.desiredHeight);
}

- (NSSize)desiredSize {
    [self view];
    return NSMakeSize(kDesiredWidth, self.desiredHeight);
}

- (CGFloat)favoritesViewHeight {
    return kDesiredHeight - NSMaxY(self.controlsView.frame);
}

- (void)viewDidAppear {
    self.controlsView.useSystemColorPicker =
        [[NSUserDefaults standardUserDefaults] boolForKey:kCPKUseSystemColorPicker];
}

- (void)selectColor:(NSColor *)color {
    self.selectedColor = color;
    self.controlsView.swatchColor = color;
    _block(color);
    [self.favoritesView selectColor:color];
}

#pragma mark - CPKSelectionViewDelegate

- (void)selectionViewContentSizeDidChange {
    [self.selectionView sizeToFit];
    self.controlsView.frame = NSMakeRect(0,
                                         NSMaxY(self.selectionView.frame),
                                         kDesiredWidth,
                                         [CPKControlsView desiredHeight]);

    self.favoritesView.frame = NSMakeRect(kLeftMargin,
                                          NSMaxY(self.controlsView.frame),
                                          kDesiredWidth - kLeftMargin - kRightMargin,
                                          [self favoritesViewHeight]);
}

@end
