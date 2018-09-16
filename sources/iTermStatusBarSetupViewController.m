//
//  iTermStatusBarSetupViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarSetupViewController.h"

#import "iTermAPIHelper.h"
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
#import "iTermStatusBarSpringComponent.h"
#import "iTermStatusBarSetupCollectionViewItem.h"
#import "iTermStatusBarSetupDestinationCollectionViewController.h"
#import "iTermStatusBarSetupElement.h"
#import "iTermStatusBarSwiftyStringComponent.h"
#import "iTermStatusBarVariableBaseComponent.h"
#import "NSArray+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"
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

@interface iTermStatusBarSetupViewController ()<NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout>

@end

@implementation iTermStatusBarSetupViewController {
    IBOutlet NSCollectionView *_collectionView;
    IBOutlet iTermStatusBarSetupDestinationCollectionViewController *_destinationViewController;
    IBOutlet CPKColorWell *_separatorColorWell;
    IBOutlet CPKColorWell *_backgroundColorWell;
    IBOutlet CPKColorWell *_defaultTextColorWell;
    IBOutlet NSTextField *_fontLabel;
    IBOutlet NSPanel *_advancedPanel;
    IBOutlet NSPopUpButton *_font;
    IBOutlet NSPopUpButton *_fontSize;
    NSArray<iTermStatusBarSetupElement *> *_elements;
    iTermStatusBarLayout *_layout;
}

- (nullable instancetype)initWithLayoutDictionary:(NSDictionary *)layoutDictionary {
    self = [super initWithNibName:@"iTermStatusBarSetupViewController" bundle:[NSBundle bundleForClass:self.class]];
    if (self) {
        _layout = [[iTermStatusBarLayout alloc] initWithDictionary:layoutDictionary
                                                             scope:nil];
    }
    return self;
}

- (iTermStatusBarSetupElement *)newElementForProviderRegistrationRequest:(ITMRPCRegistrationRequest *)request {
    iTermStatusBarRPCComponentFactory *factory =
        [[iTermStatusBarRPCComponentFactory alloc] initWithRegistrationRequest:request];
    return [[iTermStatusBarSetupElement alloc] initWithComponentFactory:factory
                                                                  knobs:factory.defaultKnobs];
}

- (void)awakeFromNib {
    NSArray<Class> *classes = @[
                                 [iTermStatusBarCPUUtilizationComponent class],
                                 [iTermStatusBarMemoryUtilizationComponent class],
                                 [iTermStatusBarNetworkUtilizationComponent class],

                                 [iTermStatusBarClockComponent class],

                                 [iTermStatusBarGitComponent class],
                                 [iTermStatusBarHostnameComponent class],
                                 [iTermStatusBarUsernameComponent class],
                                 [iTermStatusBarJobComponent class],
                                 [iTermStatusBarWorkingDirectoryComponent class],

                                 [iTermStatusBarSearchFieldComponent class],
                                 [iTermStatusBarComposerComponent class],

                                 [iTermStatusBarFixedSpacerComponent class],
                                 [iTermStatusBarSpringComponent class],

                                 [iTermStatusBarSwiftyStringComponent class],
                                 [iTermStatusBarFunctionCallComponent class],
                                 ];
    _elements = [classes mapWithBlock:^id(Class theClass) {
        iTermStatusBarBuiltInComponentFactory *factory =
            [[iTermStatusBarBuiltInComponentFactory alloc] initWithClass:theClass];
        return [[iTermStatusBarSetupElement alloc] initWithComponentFactory:factory
                                                                      knobs:factory.defaultKnobs];
    }];
    for (ITMRPCRegistrationRequest *request in iTermAPIHelper.statusBarComponentProviderRegistrationRequests) {
        iTermStatusBarSetupElement *element = [self newElementForProviderRegistrationRequest:request];
        if (element) {
            _elements = [_elements arrayByAddingObject:element];
        }
    }
    [_collectionView registerForDraggedTypes: @[iTermStatusBarElementPasteboardType]];
    [_collectionView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
    _collectionView.selectable = YES;

    [_destinationViewController setLayout:_layout];

    NSFont *font = _layout.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont];
    _fontLabel.stringValue = [NSString stringWithFormat:@"%@pt %@", @(font.pointSize), font.fontName];
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

    [super awakeFromNib];
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
    return [_destinationViewController layoutDictionaryWithAdvancedConfiguration:_layout.advancedConfiguration];
}

- (IBAction)noop:(id)sender {
}

- (IBAction)openFontPanel:(id)sender {
    _advancedPanel.nextResponder = self;
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSFontPanel *fontPanel = [fontManager fontPanel:YES];
    [fontPanel orderFront:sender];
}

- (void)changeFont:(nullable id)sender {
    NSFont *font = [sender convertFont:_layout.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont]];
    _layout.advancedConfiguration.font = font;
    _fontLabel.stringValue = [NSString stringWithFormat:@"%@pt %@", @(font.pointSize), font.fontName];
}

- (IBAction)ok:(id)sender {
    _ok = YES;
    [self endSheet];
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

- (IBAction)advancedOK:(id)sender {
    [self.view.window endSheet:_advancedPanel];
}


- (void)advancedPanelDidClose {
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSFontPanel *fontPanel = [fontManager fontPanel:YES];
    [fontPanel close];
    
    _layout.advancedConfiguration.separatorColor = _separatorColorWell.color;
    _layout.advancedConfiguration.backgroundColor = _backgroundColorWell.color;
    _layout.advancedConfiguration.defaultTextColor = _defaultTextColorWell.color;
}

- (void)endSheet {
    NSWindow *window = self.view.window;
    [window.sheetParent endSheet:window];
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
    id exemplar = _elements[index].exemplar;
    if ([exemplar isKindOfClass:[NSString class]]) {
        item.textField.stringValue = exemplar;
    } else {
        item.textField.attributedStringValue = exemplar;
    }
    item.detailText = _elements[index].shortDescription;
    item.textField.toolTip = _elements[index].detailedDescription;
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

- (BOOL)collectionView:(NSCollectionView *)collectionView
writeItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
          toPasteboard:(NSPasteboard *)pasteboard {
    [pasteboard clearContents];

    NSArray *objects = [indexPaths.allObjects mapWithBlock:^id(NSIndexPath *indexPath) {
        NSUInteger index = [indexPath indexAtPosition:1];
        return self->_elements[index];
    }];
    [pasteboard writeObjects:objects];

    return YES;
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
    return item.view.snapshot;
}

@end

NS_ASSUME_NONNULL_END
