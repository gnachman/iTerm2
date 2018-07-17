//
//  iTermStatusBarSetupViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarSetupViewController.h"

#import "iTermAPIHelper.h"
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarClockComponent.h"
#import "iTermStatusBarFixedSpacerComponent.h"
#import "iTermStatusBarFunctionCallComponent.h"
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

NS_ASSUME_NONNULL_BEGIN


@interface iTermStatusBarSetupViewController ()<NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout>

@end

@implementation iTermStatusBarSetupViewController {
    IBOutlet NSCollectionView *_collectionView;
    IBOutlet iTermStatusBarSetupDestinationCollectionViewController *_destinationViewController;
    NSArray<iTermStatusBarSetupElement *> *_elements;
    NSDictionary *_initialLayout;
}

- (nullable instancetype)initWithLayoutDictionary:(NSDictionary *)layoutDictionary {
    self = [super initWithNibName:@"iTermStatusBarSetupViewController" bundle:nil];
    if (self) {
        _initialLayout = [layoutDictionary copy];
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
    NSArray<Class> *classes = @[ [iTermStatusBarSwiftyStringComponent class],
                                 [iTermStatusBarFunctionCallComponent class],
                                 [iTermStatusBarFixedSpacerComponent class],
                                 [iTermStatusBarSpringComponent class],
                                 [iTermStatusBarClockComponent class],
                                 [iTermStatusBarHostnameComponent class],
                                 [iTermStatusBarUsernameComponent class],
                                 [iTermStatusBarWorkingDirectoryComponent class],
                                 [iTermStatusBarSearchFieldComponent class] ];
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

    [_destinationViewController setLayoutDictionary:_initialLayout];
    [super awakeFromNib];
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
    return _destinationViewController.layoutDictionary;
}

- (IBAction)ok:(id)sender {
    _ok = YES;
    [self endSheet];
}

- (IBAction)cancel:(id)sender {
    [self endSheet];
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
    iTermStatusBarSetupCollectionViewItem *item = [[iTermStatusBarSetupCollectionViewItem alloc] initWithNibName:@"iTermStatusBarSetupCollectionViewItem" bundle:nil];
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

//- draggingImageForItemsAtIndexPaths:withEvent:offset:
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

//- (NSDragOperation)collectionView:(NSCollectionView *)collectionView validateDrop:(id <NSDraggingInfo>)draggingInfo proposedIndexPath:(NSIndexPath * __nonnull * __nonnull)proposedDropIndexPath dropOperation:(NSCollectionViewDropOperation *)proposedDropOperation NS_AVAILABLE_MAC(10_11);
// - (BOOL)collectionView:(NSCollectionView *)collectionView acceptDrop:(id <NSDraggingInfo>)draggingInfo indexPath:(NSIndexPath *)indexPath dropOperation:(NSCollectionViewDropOperation)dropOperation NS_AVAILABLE_MAC(10_11);

//- (nullable id <NSPasteboardWriting>)collectionView:(NSCollectionView *)collectionView
//                 pasteboardWriterForItemAtIndexPath:(NSIndexPath *)indexPath {
//    NSUInteger index = [indexPath indexAtPosition:1];
//    return _elements[index];
//}

//- (void)collectionView:(NSCollectionView *)collectionView draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths NS_AVAILABLE_MAC(10_11);
// - (void)collectionView:(NSCollectionView *)collectionView draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint dragOperation:(NSDragOperation)operation;
// - (void)collectionView:(NSCollectionView *)collectionView updateDraggingItemsForDrag:(id <NSDraggingInfo>)draggingInfo;

// - (NSSet<NSIndexPath *> *)collectionView:(NSCollectionView *)collectionView shouldChangeItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths toHighlightState:(NSCollectionViewItemHighlightState)highlightState NS_AVAILABLE_MAC(10_11);
// - (void)collectionView:(NSCollectionView *)collectionView didChangeItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths toHighlightState:(NSCollectionViewItemHighlightState)highlightState NS_AVAILABLE_MAC(10_11);
// - (NSSet<NSIndexPath *> *)collectionView:(NSCollectionView *)collectionView shouldSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths NS_AVAILABLE_MAC(10_11);
// - (NSSet<NSIndexPath *> *)collectionView:(NSCollectionView *)collectionView shouldDeselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths NS_AVAILABLE_MAC(10_11);
// - (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths NS_AVAILABLE_MAC(10_11);
// - (void)collectionView:(NSCollectionView *)collectionView didDeselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths NS_AVAILABLE_MAC(10_11);

@end

NS_ASSUME_NONNULL_END
