//
//  iTermStatusBarSetupDestinationCollectionViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarSetupDestinationCollectionViewController.h"

#import "DebugLogging.h"
#import "iTermStatusBarSetupCollectionViewItem.h"
#import "iTermStatusBarSetupConfigureComponentWindowController.h"
#import "iTermStatusBarSetupKnobsViewController.h"
#import "iTermStatusBarLayout.h"
#import "iTermStatusBarTextComponent.h"

#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"

@interface iTermNoFirstResponderCollectionView : NSCollectionView
@end

@implementation iTermNoFirstResponderCollectionView

- (BOOL)canBecomeKeyView {
    return NO;
}

- (BOOL)becomeFirstResponder {
    return NO;
}

@end

@interface iTermStatusBarSetupDestinationCollectionView : NSCollectionView
@end

@implementation iTermStatusBarSetupDestinationCollectionView

- (BOOL)canBecomeKeyView {
    return YES;
}

- (BOOL)becomeFirstResponder {
    [super becomeFirstResponder];
    return YES;
}

- (void)doCommandBySelector:(SEL)selector {
    if ([self.delegate respondsToSelector:selector]) {
        NSObject *delegate = [NSObject castFrom:self.delegate];
        [delegate it_performNonObjectReturningSelector:selector withObject:self];
    }
}

@end

@interface iTermStatusBarSetupDestinationCollectionViewController ()<
    iTermStatusBarSetupElementDelegate,
    NSCollectionViewDataSource,
    NSCollectionViewDelegateFlowLayout>

@end

@implementation iTermStatusBarSetupDestinationCollectionViewController {
    NSMutableArray<iTermStatusBarSetupElement *> *_elements;
    NSIndexPath *_draggingIndexPath;
    IBOutlet NSButton *_configureButton;
    BOOL _updatingAutoRainbowColors;
}

- (void)awakeFromNib {
    _elements = [NSMutableArray array];
    [self.collectionView registerForDraggedTypes: @[iTermStatusBarElementPasteboardType]];
    [self.collectionView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
    self.collectionView.selectable = YES;
    [super awakeFromNib];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _configureButton.enabled = NO;
    [self.collectionView registerClass:[iTermStatusBarSetupCollectionViewItem class]
                 forItemWithIdentifier:@"element"];
}

- (void)deleteSelected {
    NSSet<NSIndexPath *> *selections = [self.collectionView selectionIndexPaths];
    if (selections.count == 0) {
        return;
    }
    NSInteger selectedIndex = [selections.anyObject indexAtPosition:1];
    [self deleteItemAtIndex:selectedIndex];
    _configureButton.enabled = NO;
}

- (void)deleteItemAtIndex:(NSInteger)index {
    NSRect rectInWindowCoords = [self.collectionView convertRect:[self.collectionView frameForItemAtIndex:index] toView:nil];
    NSRect rect = [self.collectionView.window convertRectToScreen:rectInWindowCoords];
    NSShowAnimationEffect(NSAnimationEffectPoof,
                          NSMakePoint(NSMidX(rect), NSMidY(rect)),
                          NSZeroSize,
                          nil,
                          nil,
                          NULL);
    [[[self.collectionView itemAtIndex:index] view] setHidden:YES];
    [self.collectionView.animator performBatchUpdates:
     ^{
         [self->_elements removeObjectAtIndex:index];
         NSIndexPath *indexPath = [NSIndexPath indexPathForItem:index inSection:0];
         [self.collectionView deleteItemsAtIndexPaths:[NSSet setWithObject:indexPath]];
     } completionHandler:^(BOOL finished) {}];
    [self didChange:YES];
}

- (NSCollectionView *)collectionView {
    return [NSCollectionView castFrom:self.view];
}

- (void)setElements:(NSArray<iTermStatusBarSetupElement *> *)elements {
    _elements = [elements mutableCopy];
    [self.collectionView reloadData];
}

- (void)updateAutoRainbowColors {
    if (_updatingAutoRainbowColors) {
        return;
    }
    iTermStatusBarAutoRainbowController *controller = [[iTermStatusBarAutoRainbowController alloc] initWithStyle:_advancedConfiguration.autoRainbowStyle];
    controller.darkBackground = self.darkBackground;
    _updatingAutoRainbowColors = YES;
    [controller enumerateColorsWithCount:_elements.count block:^(NSInteger i, NSColor *color) {
        id<iTermStatusBarComponent> component = _elements[i].component;
        NSMutableDictionary *knobValues = [component.configuration[iTermStatusBarComponentConfigurationKeyKnobValues] mutableCopy];
        knobValues[iTermStatusBarSharedTextColorKey] = [color dictionaryValue];
        [component statusBarComponentSetKnobValues:knobValues];
    }];
    _updatingAutoRainbowColors = NO;
}

- (void)setAdvancedConfiguration:(iTermStatusBarAdvancedConfiguration *)advancedConfiguration {
    _advancedConfiguration = advancedConfiguration;
    iTermStatusBarLayout *temporaryLayout = [[iTermStatusBarLayout alloc] initWithDictionary:[self layoutDictionary] scope:nil];
    [self loadElementsFromLayout:temporaryLayout];
    [self updateAutoRainbowColors];
    [self didChange:YES];
}

- (void)loadElementsFromLayout:(iTermStatusBarLayout *)layout {
    [self->_elements removeAllObjects];
    [layout.components enumerateObjectsUsingBlock:^(id<iTermStatusBarComponent>  _Nonnull component, NSUInteger idx, BOOL * _Nonnull stop) {
        iTermStatusBarSetupElement *element = [[iTermStatusBarSetupElement alloc] initWithComponent:component];
        element.delegate = self;
        [self->_elements addObject:element];
    }];
    [self.collectionView reloadData];
    [self updateAutoRainbowColors];
}

- (void)setLayout:(iTermStatusBarLayout *)layout {
    _advancedConfiguration = layout.advancedConfiguration;
    [self loadElementsFromLayout:layout];
}

- (NSDictionary *)layoutDictionary {
    NSArray<id<iTermStatusBarComponent>> *components = [_elements mapWithBlock:^id(iTermStatusBarSetupElement *element) {
        return element.component;
    }];
    iTermStatusBarLayout *layout = [[iTermStatusBarLayout alloc] initWithComponents:components
                                                              advancedConfiguration:_advancedConfiguration];
    return layout.dictionaryValue;
}

- (void)deleteBackward:(id)sender {
    [self deleteSelected];
}

- (void)configureStatusBarComponentWithIdentifier:(NSString *)identifier {
    NSInteger index = [_elements indexOfObjectPassingTest:^BOOL(iTermStatusBarSetupElement * _Nonnull element, NSUInteger idx, BOOL * _Nonnull stop) {
        return [element.component.statusBarComponentIdentifier isEqualToString:identifier];
    }];
    if (index == NSNotFound) {
        return;
    }
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:index inSection:0];
    NSSet<NSIndexPath *> *indexPaths = [NSSet setWithObject:indexPath];
    [self.collectionView selectItemsAtIndexPaths:indexPaths scrollPosition:NSCollectionViewScrollPositionCenteredVertically];
    [self collectionView:self.collectionView didSelectItemsAtIndexPaths:indexPaths];
    if (_configureButton.enabled) {
        [_configureButton.target it_performNonObjectReturningSelector:_configureButton.action withObject:_configureButton];
    }
}

- (void)didChange:(BOOL)updateAutoRainbow {
    if (updateAutoRainbow) {
        [self updateAutoRainbowColors];
    }
    if (self.onChange) {
        self.onChange();
    }
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return _elements.count;
}

- (iTermStatusBarSetupCollectionViewItem *)newItemWithIndexPath:(NSIndexPath *)indexPath {
    iTermStatusBarSetupCollectionViewItem *item =
        [self.collectionView makeItemWithIdentifier:@"element" forIndexPath:indexPath];
    [self initializeItem:item atIndexPath:indexPath];
    [item sizeToFit];
    return item;
}

- (void)initializeItem:(iTermStatusBarSetupCollectionViewItem *)item
           atIndexPath:(NSIndexPath *)indexPath {
    const NSInteger index = [indexPath indexAtPosition:1];
    NSFont *font = nil;
    if ([_elements[index].component respondsToSelector:@selector(font)]) {
        font = [_elements[index].component font];
    }
    if (!font) {
        font = _advancedConfiguration.font;
    }
    item.textField.attributedStringValue = [_elements[index] exemplarWithBackgroundColor:_advancedConfiguration.backgroundColor
                                                                               textColor:_advancedConfiguration.defaultTextColor ?: self.defaultTextColor
                                                                             defaultFont:font];

    item.hideDetail = YES;
    item.textField.toolTip = _elements[index].detailedDescription;
    item.backgroundColor = _elements[index].component.statusBarBackgroundColor ?: _advancedConfiguration.backgroundColor ?: self.defaultBackgroundColor;
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

#pragma mark Drag and drop support

- (BOOL)collectionView:(NSCollectionView *)collectionView
canDragItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
             withEvent:(NSEvent *)event {
    _draggingIndexPath = indexPaths.anyObject;
    return YES;
}

- (void)collectionView:(NSCollectionView *)collectionView draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forItemsAtIndexes:(NSIndexSet *)indexes {
    session.animatesToStartingPositionsOnCancelOrFail = NO;
}

- (void)collectionView:(NSCollectionView *)collectionView
       draggingSession:(NSDraggingSession *)session
          endedAtPoint:(NSPoint)screenPoint
         dragOperation:(NSDragOperation)operation {
    if (!_draggingIndexPath) {
        return;
    }

    NSPoint windowPoint = [collectionView.window convertRectFromScreen:NSMakeRect(screenPoint.x,
                                                                                  screenPoint.y,
                                                                                  0,
                                                                                  0)].origin;
    NSPoint collectionViewPoint = [collectionView convertPoint:windowPoint fromView:nil];
    if (operation == NSDragOperationNone && !NSPointInRect(collectionViewPoint, collectionView.bounds)) {
        [self deleteItemAtIndex:[self->_draggingIndexPath indexAtPosition:1]];
    }
    _draggingIndexPath = nil;
}

- (id<NSPasteboardWriting>)collectionView:(NSCollectionView *)collectionView pasteboardWriterForItemAtIndex:(NSUInteger)index {
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setData:[NSData it_dataWithArchivedObject:_elements[index]]
            forType:iTermStatusBarElementPasteboardType];
    return pbItem;
}

//- draggingImageForItemsAtIndexPaths:withEvent:offset:
- (NSImage *)collectionView:(NSCollectionView *)collectionView
draggingImageForItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
                  withEvent:(NSEvent *)event
                     offset:(NSPointPointer)dragImageOffset {
    NSPoint locationInWindow = event.locationInWindow;
    iTermStatusBarSetupCollectionViewItem *item = [iTermStatusBarSetupCollectionViewItem castFrom:[collectionView itemAtIndexPath:indexPaths.anyObject]];
    assert(item);
    NSPoint locationInItem = [item.view convertPoint:locationInWindow fromView:nil];
    NSPoint center = NSMakePoint(item.view.frame.size.width / 2,
                                 item.view.frame.size.height / 2);
    *dragImageOffset = NSMakePoint(center.x - locationInItem.x,
                                   center.y - locationInItem.y);
    return item.view.snapshot;
}

- (NSDragOperation)collectionView:(NSCollectionView *)collectionView
                     validateDrop:(id <NSDraggingInfo>)draggingInfo
                proposedIndexPath:(NSIndexPath * __nonnull * __nonnull)proposedDropIndexPath
                    dropOperation:(NSCollectionViewDropOperation *)proposedDropOperation {
    if (draggingInfo.draggingSource != collectionView &&
        draggingInfo.draggingSource != _sourceCollectionView) {
        return NSDragOperationNone;
    }

    *proposedDropOperation = NSCollectionViewDropBefore;
    if ([draggingInfo.draggingSource isKindOfClass:[self class]]) {
        return NSDragOperationMove;
    } else {
        return NSDragOperationMove;
    }
}

- (BOOL)collectionView:(NSCollectionView *)collectionView
            acceptDrop:(id<NSDraggingInfo>)draggingInfo
             indexPath:(NSIndexPath *)indexPath
         dropOperation:(NSCollectionViewDropOperation)dropOperation {
    __block NSData *data = nil;
    [draggingInfo enumerateDraggingItemsWithOptions:0 forView:collectionView classes:@[[NSPasteboardItem class]] searchOptions:@{} usingBlock:^(NSDraggingItem * _Nonnull draggingItem, NSInteger idx, BOOL * _Nonnull stop) {
        NSPasteboardItem *item = draggingItem.item;
        data = [item dataForType:iTermStatusBarElementPasteboardType];
    }];
    if (!data) {
        DLog(@"No objects on pasteboard");
        return NO;
    }
    NSError *error = nil;
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
    unarchiver.requiresSecureCoding = NO;
    iTermStatusBarSetupElement *element = [data it_unarchivedObjectOfClasses:@[ [iTermStatusBarSetupElement class] ]];
    if (error || !element) {
        DLog(@"Reject drop: %@", error);
        return NO;
    }
    element.delegate = self;
    [collectionView.animator performBatchUpdates:^{
        if (draggingInfo.draggingSource == collectionView) {
            const NSInteger fromIndex = [self->_draggingIndexPath indexAtPosition:1];
            const NSInteger toIndex = [indexPath indexAtPosition:1];
            NSLog(@"Move element from %@ to %@", @(fromIndex), @(toIndex));
            if (fromIndex >= toIndex) {
                [self->_elements removeObjectAtIndex:fromIndex];
                [collectionView moveItemAtIndexPath:self->_draggingIndexPath
                                        toIndexPath:indexPath];
            }
            [self->_elements insertObject:element atIndex:toIndex];
            if (fromIndex < toIndex) {
                [self->_elements removeObjectAtIndex:fromIndex];
                [collectionView moveItemAtIndexPath:self->_draggingIndexPath
                                        toIndexPath:[NSIndexPath indexPathForItem:toIndex - 1 inSection:0]];
            }
            NSLog(@"Collection move item from %@ to %@", self->_draggingIndexPath, indexPath);
        } else {
            [self->_elements insertObject:element atIndex:[indexPath indexAtPosition:1]];
            [collectionView insertItemsAtIndexPaths:[NSSet setWithObject:indexPath]];
        }
    } completionHandler:^(BOOL finished) {}];
    [self didChange:YES];
    return YES;
}

- (NSSet<NSIndexPath *> *)collectionView:(NSCollectionView *)collectionView shouldChangeItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths toHighlightState:(NSCollectionViewItemHighlightState)highlightState {
    return indexPaths;
}

- (void)collectionView:(NSCollectionView *)collectionView didChangeItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths toHighlightState:(NSCollectionViewItemHighlightState)highlightState {
    [indexPaths enumerateObjectsUsingBlock:^(NSIndexPath * _Nonnull indexPath, BOOL * _Nonnull stop) {
        [[collectionView itemAtIndexPath:indexPath] setHighlightState:highlightState];
    }];
    [self didChange:NO];
}

- (NSSet<NSIndexPath *> *)collectionView:(NSCollectionView *)collectionView shouldSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    return indexPaths;
}

- (NSSet<NSIndexPath *> *)collectionView:(NSCollectionView *)collectionView shouldDeselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    return indexPaths;
}

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (!indexPath) {
        return;
    }

    const NSInteger index = [indexPath indexAtPosition:1];
    iTermStatusBarSetupElement *element = _elements[index];
    id<iTermStatusBarComponent> component = element.component;
    _configureButton.enabled = ([[component statusBarComponentKnobs] count] > 0);
}

- (iTermStatusBarSetupKnobsViewController *)viewControllerToConfigureComponent:(id<iTermStatusBarComponent>)component {
    return [[iTermStatusBarSetupKnobsViewController alloc] initWithComponent:component];
}

- (void)collectionView:(NSCollectionView *)collectionView didDeselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    _configureButton.enabled = collectionView.selectionIndexPaths.count > 0;
}

#pragma mark - iTermStatusBarSetupElementDelegate

- (BOOL)keysContainsTextColor:(NSSet<NSString *> *)keys {
    for (NSString *key in keys) {
        if ([key isEqualToString:iTermStatusBarSharedTextColorKey]) {
            return YES;
        }
    }
    return NO;
}

- (void)disableAutoRainbow {
    iTermStatusBarAdvancedConfiguration *config = [self.advancedConfiguration copy];
    config.autoRainbowStyle = iTermStatusBarAutoRainbowStyleDisabled;
    self.advancedConfiguration = config;
}

- (void)itermStatusBarSetupElementDidChange:(iTermStatusBarSetupElement *)element
                                updatedKeys:(NSSet<NSString *> *)updatedKeys {
    NSInteger index = [_elements indexOfObject:element];
    if (index == NSNotFound) {
        return;
    }
    if (!_updatingAutoRainbowColors &&
        [self keysContainsTextColor:updatedKeys]) {
        [self disableAutoRainbow];
    }
    [self.collectionView.animator performBatchUpdates:
     ^{
         NSIndexPath *indexPath = [NSIndexPath indexPathForItem:index inSection:0];
         [self.collectionView reloadItemsAtIndexPaths:[NSSet setWithObject:indexPath]];
     } completionHandler:^(BOOL finished) {}];
    [self didChange:YES];
}

#pragma mark - Actions

- (IBAction)configureComponent:(id)sender {
    NSIndexPath *indexPath = [self.collectionView.selectionIndexPaths anyObject];
    if (!indexPath) {
        return;
    }
    
    iTermStatusBarSetupElement *element = _elements[indexPath.item];
    id<iTermStatusBarComponent> component = element.component;
    if (!component) {
        return;
    }
    
    iTermStatusBarSetupKnobsViewController *viewController = [self viewControllerToConfigureComponent:component];
    viewController.view.frame = NSMakeRect(0, 0, viewController.preferredContentSize.width, viewController.preferredContentSize.height);
    iTermStatusBarSetupConfigureComponentWindowController *windowController =
    [[iTermStatusBarSetupConfigureComponentWindowController alloc] initWithWindowNibName:@"iTermStatusBarSetupConfigureComponentWindowController"];
    [windowController window];
    [windowController setKnobsViewController:viewController];
    [self.view.window beginSheet:windowController.window completionHandler:^(NSModalResponse returnCode) {
        self->_configureButton.enabled = NO;
        if (returnCode == NSModalResponseOK) {
            [viewController commit];
            [component statusBarComponentSetKnobValues:viewController.knobValues];
        }
        [windowController description];  // Hold on to the window controller
    }];
}

@end

