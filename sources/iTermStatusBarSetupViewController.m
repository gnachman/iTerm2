//
//  iTermStatusBarSetupViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarSetupViewController.h"

#import "iTermAPIHelper.h"
#import "iTermFontPanel.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermStatusBarActionComponent.h"
#import "iTermStatusBarBatteryComponent.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarCPUUtilizationComponent.h"
#import "iTermStatusBarClockComponent.h"
#import "iTermStatusBarComposerComponent.h"
#import "iTermStatusBarFixedSpacerComponent.h"
#import "iTermStatusBarFunctionCallComponent.h"
#import "iTermStatusBarGitComponent.h"
#import "iTermStatusBarGraphicComponent.h"
#import "iTermStatusBarJobComponent.h"
#import "iTermStatusBarLayout.h"
#import "iTermStatusBarMemoryUtilizationComponent.h"
#import "iTermStatusBarNetworkUtilizationComponent.h"
#import "iTermStatusBarRPCProvidedTextComponent.h"
#import "iTermStatusBarSearchFieldComponent.h"
#import "iTermStatusBarSnippetComponent.h"
#import "iTermStatusBarSpringComponent.h"
#import "iTermStatusBarSetupCollectionViewItem.h"
#import "iTermStatusBarSetupDestinationCollectionViewController.h"
#import "iTermStatusBarSetupElement.h"
#import "iTermStatusBarSwiftyStringComponent.h"
#import "iTermStatusBarVariableBaseComponent.h"
#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import <ColorPicker/ColorPicker.h>

NS_ASSUME_NONNULL_BEGIN


@interface iTermStatusBarAdvancedConfigurationPanel : NSPanel
@end

@implementation iTermStatusBarAdvancedConfigurationPanel

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

@end

@interface iTermStatusBarSetupViewController ()<NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, NSFontChanging, NSMenuItemValidation>

@end

@implementation iTermStatusBarSetupViewController {
    IBOutlet NSCollectionView *_collectionView;
    IBOutlet iTermStatusBarSetupDestinationCollectionViewController *_destinationViewController;
    IBOutlet CPKColorWell *_separatorColorWell;
    IBOutlet CPKColorWell *_backgroundColorWell;
    IBOutlet CPKColorWell *_defaultTextColorWell;
    IBOutlet NSTextField *_fontLabel;
    IBOutlet NSPanel *_advancedPanel;
    IBOutlet NSButton *_tightPacking;
    IBOutlet NSButton *_removeEmptyComponents;
    IBOutlet NSPopUpButton *_autoRainbow;
    NSArray<iTermStatusBarSetupElement *> *_elements;
    iTermStatusBarLayout *_layout;
    BOOL _darkBackground;
    BOOL _allowRainbow;
}

- (nullable instancetype)initWithLayoutDictionary:(NSDictionary *)layoutDictionary
                                   darkBackground:(BOOL)darkBackground
                                     allowRainbow:(BOOL)allowRainbow
                                      profileType:(ProfileType)profileType {
    self = [super initWithNibName:@"iTermStatusBarSetupViewController" bundle:[NSBundle bundleForClass:self.class]];
    if (self) {
        _profileType = profileType;
        _layout = [[iTermStatusBarLayout alloc] initWithDictionary:layoutDictionary
                                                             scope:nil];
        _darkBackground = darkBackground;
        _allowRainbow = allowRainbow;
    }
    return self;
}

- (iTermStatusBarSetupElement *)newElementForProviderRegistrationRequest:(ITMRPCRegistrationRequest *)request {
    iTermStatusBarRPCComponentFactory *factory =
        [[iTermStatusBarRPCComponentFactory alloc] initWithRegistrationRequest:request];
    return [[iTermStatusBarSetupElement alloc] initWithComponentFactory:factory
                                                        layoutAlgorithm:_layout.advancedConfiguration.layoutAlgorithm
                                                                  knobs:factory.defaultKnobs];
}

- (void)loadElements {
    NSArray<Class> *classes = @[
                                 [iTermStatusBarBatteryComponent class],
                                 [iTermStatusBarCPUUtilizationComponent class],
                                 [iTermStatusBarMemoryUtilizationComponent class],
                                 [iTermStatusBarNetworkUtilizationComponent class],

                                 [iTermStatusBarClockComponent class],
                                 [iTermStatusBarActionComponent class],
                                 [iTermStatusBarActionMenuComponent class],
                                 [iTermStatusBarSnippetMenuComponent class],
                                 [iTermStatusBarTriggersComponent class],

                                 [iTermStatusBarGitComponent class],
                                 [iTermStatusBarHostnameComponent class],
                                 [iTermStatusBarUsernameComponent class],
                                 [iTermStatusBarJobComponent class],
                                 [iTermStatusBarWorkingDirectoryComponent class],

                                 [iTermStatusBarSearchFieldComponent class],
                                 [iTermStatusBarFilterComponent class],
                                 [iTermStatusBarComposerComponent class],

                                 [iTermStatusBarFixedSpacerComponent class],
                                 [iTermStatusBarSpringComponent class],

                                 [iTermStatusBarSwiftyStringComponent class],
                                 [iTermStatusBarFunctionCallComponent class],
                                 ];
    classes = [classes filteredArrayUsingBlock:^BOOL(Class c) {
        return ((ProfileType)[c compatibleProfileTypes] & _profileType) != 0;
    }];
    _elements = [classes mapWithBlock:^id(Class theClass) {
        iTermStatusBarBuiltInComponentFactory *factory =
            [[iTermStatusBarBuiltInComponentFactory alloc] initWithClass:theClass];
        return [[iTermStatusBarSetupElement alloc] initWithComponentFactory:factory
                                                            layoutAlgorithm:self->_layout.advancedConfiguration.layoutAlgorithm
                                                                      knobs:factory.defaultKnobs];
    }];
}

- (void)awakeFromNib {
    _destinationViewController.profileType = _profileType;
    _destinationViewController.defaultBackgroundColor = self.defaultBackgroundColor;
    _destinationViewController.defaultTextColor = self.defaultTextColor;
    _destinationViewController.sourceCollectionView = _collectionView;

    [self loadElements];
    for (ITMRPCRegistrationRequest *request in iTermAPIHelper.statusBarComponentProviderRegistrationRequests) {
        iTermStatusBarSetupElement *element = [self newElementForProviderRegistrationRequest:request];
        if (element) {
            _elements = [_elements arrayByAddingObject:element];
        }
    }
    [_collectionView registerForDraggedTypes: @[iTermStatusBarElementPasteboardType]];
    [_collectionView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
    _collectionView.selectable = YES;

    [_autoRainbow selectItemWithTag:_layout.advancedConfiguration.autoRainbowStyle];

    _destinationViewController.darkBackground = _darkBackground;
    _destinationViewController.advancedConfiguration = _layout.advancedConfiguration;

    [_destinationViewController setLayout:_layout];

    __weak __typeof(self) weakSelf = self;
    _destinationViewController.onChange = ^{
        [weakSelf apply];
    };
    [self setFont:_layout.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont]];
    [self initializeColorWell:_separatorColorWell
                   withAction:@selector(noop:)
                        color:_layout.advancedConfiguration.separatorColor
                 alphaAllowed:YES];
    [self initializeColorWell:_backgroundColorWell
                   withAction:@selector(noop:)
                        color:_layout.advancedConfiguration.backgroundColor
                 alphaAllowed:NO];
    [self initializeColorWell:_defaultTextColorWell
                   withAction:@selector(noop:)
                        color:_layout.advancedConfiguration.defaultTextColor
                 alphaAllowed:NO];
    [self initializeUI];

    [super awakeFromNib];
}

- (void)initializeUI {
    switch (_layout.advancedConfiguration.layoutAlgorithm) {
        case iTermStatusBarLayoutAlgorithmSettingStable:
            _tightPacking.state = NSControlStateValueOff;
            break;
        case iTermStatusBarLayoutAlgorithmSettingTightlyPacked:
            _tightPacking.state = NSControlStateValueOn;
            break;
    }

    _removeEmptyComponents.state = _layout.advancedConfiguration.removeEmptyComponents ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)initializeColorWell:(CPKColorWell *)colorWell
                 withAction:(SEL)selector
                      color:(NSColor *)color
               alphaAllowed:(BOOL)alphaAllowed {
    colorWell.color = color;
    colorWell.noColorAllowed = YES;
    colorWell.alphaAllowed = alphaAllowed;
    colorWell.target = self;
    colorWell.action = selector;
    colorWell.continuous = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_collectionView registerClass:[iTermStatusBarSetupCollectionViewItem class]
             forItemWithIdentifier:@"element"];
}

- (void)deleteBackward:(nullable id)sender {
    [_destinationViewController deleteSelected];
}

- (NSDictionary *)layoutDictionary {
    return [_destinationViewController layoutDictionary];
}

- (IBAction)noop:(id)sender {
}

- (NSView *)fontPanelAccessory {
    NSButton *button = [[NSButton alloc] init];
    button.title = @"Reset to System Font";
    button.buttonType = NSButtonTypeMomentaryPushIn;
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = @selector(resetFont:);
    button.autoresizingMask = (NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin);
    [button sizeToFit];

    NSView *wrapper = [[NSView alloc] init];
    wrapper.frame = button.bounds;
    [wrapper addSubview:button];
    wrapper.autoresizesSubviews = YES;

    return wrapper;
}

- (IBAction)openFontPanel:(id)sender {
    _advancedPanel.nextResponder = self;
    NSFontPanel *fontPanel = [[NSFontManager sharedFontManager] fontPanel:YES];
    [fontPanel setAccessoryView:[self fontPanelAccessory]];
    NSFont *theFont = _layout.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont];
    [[NSFontManager sharedFontManager] setSelectedFont:theFont isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
- (NSFontPanelModeMask)validModesForFontPanel:(NSFontPanel *)fontPanel {
#pragma clang diagnostic pop
    return kValidModesForFontPanel;
}

- (IBAction)resetFont:(id)sender {
    [self setFont:[iTermStatusBarAdvancedConfiguration defaultFont]];
}

- (void)changeFont:(nullable id)sender {
    NSFont *font = [sender convertFont:_layout.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont]];
    [self setFont:font];
}

- (void)setFont:(NSFont *)font {
    _layout.advancedConfiguration.font = font;

    if ([font isEqual:[iTermStatusBarAdvancedConfiguration defaultFont]]) {
        _fontLabel.stringValue = @"System Font";
        return;
    }
    _fontLabel.stringValue = [NSString stringWithFormat:@"%@pt %@", @(font.pointSize), font.fontName];
}

- (IBAction)ok:(id)sender {
    _ok = YES;
    [self endSheet];
}

- (void)apply {
    if (self.applyBlock) {
        self.applyBlock(self.layoutDictionary);
    }
    const NSInteger tag = _destinationViewController.advancedConfiguration.autoRainbowStyle;
    [_autoRainbow selectItemWithTag:tag];
    const NSInteger index = [_autoRainbow indexOfItemWithTag:tag];
    if (index != NSNotFound) {
        _autoRainbow.title = [_autoRainbow.menu.itemArray[index] title];
    } else {
        _autoRainbow.title = _autoRainbow.menu.itemArray.firstObject.title;
    }
}

- (IBAction)cancel:(id)sender {
    [self endSheet];
}

- (IBAction)advanced:(id)sender {
    __weak __typeof(self) weakSelf = self;
    [self.view.window beginSheet:_advancedPanel completionHandler:^(NSModalResponse returnCode) {
        [weakSelf advancedPanelDidClose];
    }];
}

- (IBAction)autoRainbow:(id)sender {
    NSPopUpButton *control = sender;
    iTermStatusBarAdvancedConfiguration *config = [_destinationViewController.advancedConfiguration copy];
    config.autoRainbowStyle = control.selectedTag;
    _destinationViewController.advancedConfiguration = config;
}

- (IBAction)advancedOK:(id)sender {
    [self.view.window endSheet:_advancedPanel];
}

- (IBAction)help:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://iterm2.com/status-bar-layout"]];
}

- (void)advancedPanelDidClose {
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSFontPanel *fontPanel = [fontManager fontPanel:YES];
    [fontPanel close];

    _layout.advancedConfiguration.separatorColor = _separatorColorWell.color;
    _layout.advancedConfiguration.backgroundColor = _backgroundColorWell.color;
    _layout.advancedConfiguration.defaultTextColor = _defaultTextColorWell.color;
    _layout.advancedConfiguration.layoutAlgorithm = (_tightPacking.state == NSControlStateValueOn) ? iTermStatusBarLayoutAlgorithmSettingTightlyPacked : iTermStatusBarLayoutAlgorithmSettingStable;
    _layout.advancedConfiguration.removeEmptyComponents = (_removeEmptyComponents.state == NSControlStateValueOn);
    _layout.delegate = nil;

    _layout = [[iTermStatusBarLayout alloc] initWithDictionary:_layout.dictionaryValue scope:nil];

    _destinationViewController.advancedConfiguration = _layout.advancedConfiguration;
    [self loadElements];
    [_collectionView reloadData];
}

- (void)endSheet {
    NSWindow *window = self.view.window;
    [window.sheetParent endSheet:window];
}

- (void)configureStatusBarComponentWithIdentifier:(NSString *)identifier {
    [_destinationViewController configureStatusBarComponentWithIdentifier:identifier];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(autoRainbow:)) {
        menuItem.state = (_destinationViewController.advancedConfiguration.autoRainbowStyle == menuItem.tag);
    }
    return YES;
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return _elements.count;
}

- (iTermStatusBarSetupCollectionViewItem *)newItemWithIndexPath:(NSIndexPath *)indexPath {
    iTermStatusBarSetupCollectionViewItem *item =
        [_collectionView makeItemWithIdentifier:@"element" forIndexPath:indexPath];
    [self initializeItem:item atIndexPath:indexPath];
    [item sizeToFit];
    return item;
}

- (void)initializeItem:(iTermStatusBarSetupCollectionViewItem *)item atIndexPath:(NSIndexPath *)indexPath {
    const NSInteger index = [indexPath indexAtPosition:1];
    item.textField.attributedStringValue = [_elements[index] exemplarWithBackgroundColor:_layout.advancedConfiguration.backgroundColor
                                                                               textColor:_layout.advancedConfiguration.defaultTextColor
                                                                             defaultFont:_layout.advancedConfiguration.font];
    item.detailText = _elements[index].shortDescription;
    item.textField.toolTip = _elements[index].detailedDescription;
    item.backgroundColor = _layout.advancedConfiguration.backgroundColor;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    return [self newItemWithIndexPath:indexPath];
}

#pragma mark - NSCollectionViewDelegateFlowLayout

- (NSSize)collectionView:(NSCollectionView *)collectionView
                  layout:(NSCollectionViewLayout*)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    iTermStatusBarSetupCollectionViewItem *item = [[iTermStatusBarSetupCollectionViewItem alloc] initWithNibName:@"iTermStatusBarSetupCollectionViewItem" bundle:[NSBundle bundleForClass:self.class]];
    [item view];
    [self initializeItem:item atIndexPath:indexPath];
    [item sizeToFit];
    return item.view.frame.size;
}

#pragma mark - NSCollectionViewDelegate

- (BOOL)collectionView:(NSCollectionView *)collectionView
canDragItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
             withEvent:(NSEvent *)event {
    return YES;
}

- (nullable id<NSPasteboardWriting>)collectionView:(NSCollectionView *)collectionView pasteboardWriterForItemAtIndex:(NSUInteger)index {
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setData:[NSData it_dataWithArchivedObject:_elements[index]]
            forType:iTermStatusBarElementPasteboardType];
    return pbItem;
}

- (NSImage *)collectionView:(NSCollectionView *)collectionView draggingImageForItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
                  withEvent:(NSEvent *)event
                     offset:(NSPointPointer)dragImageOffset {
    NSPoint locationInWindow = event.locationInWindow;
    iTermStatusBarSetupCollectionViewItem *item = [self newItemWithIndexPath:indexPaths.anyObject];
    item.hideDetail = YES;
    [item sizeToFit];
    assert(item);

    iTermStatusBarSetupCollectionViewItem *originalItem = [iTermStatusBarSetupCollectionViewItem castFrom:[collectionView itemAtIndexPath:indexPaths.anyObject]];

    NSPoint locationInItem = [originalItem.view convertPoint:locationInWindow fromView:nil];
    NSPoint center = NSMakePoint(originalItem.view.frame.size.width / 2,
                                 originalItem.view.frame.size.height / 2);
    const CGFloat heightDifference = originalItem.view.frame.size.height - item.view.frame.size.height;
    *dragImageOffset = NSMakePoint(center.x - locationInItem.x,
                                   center.y - locationInItem.y + heightDifference / 2);

    NSVisualEffectView *vev = [[NSVisualEffectView alloc] initWithFrame:item.view.bounds];
    [vev addSubview:item.view];
    [self.view addSubview:vev];
    NSImage *image = item.view.snapshot;
    [vev removeFromSuperview];
    return image;
}

@end

NS_ASSUME_NONNULL_END
