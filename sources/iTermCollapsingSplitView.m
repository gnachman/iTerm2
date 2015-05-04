//
//  iTermCollapsingSplitView.m
//  iTerm2
//
//  Created by George Nachman on 5/2/15.
//
//

#import "iTermCollapsingSplitView.h"
#import "iTermDragHandleView.h"

@interface iTermCollapsedItemView : NSView
- (instancetype)initWithFrame:(NSRect)frameRect name:(NSString *)name;
- (BOOL)isEqual:(id)object;
@end

@implementation iTermCollapsedItemView {
    NSString *_name;
}

- (instancetype)initWithFrame:(NSRect)frameRect name:(NSString *)name {
    self = [super initWithFrame:frameRect];
    if (self) {
        assert(name);
        _name = [name copy];
    }
    return self;
}

- (void)dealloc {
    [_name release];
    [super dealloc];
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:self.class];
    iTermCollapsedItemView *other = object;
    return [other->_name isEqualToString:_name];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor grayColor] set];
    NSRectFill(dirtyRect);

    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:10],
                                  NSForegroundColorAttributeName: [NSColor whiteColor] };

    [_name drawAtPoint:NSMakePoint(0, 0) withAttributes:attributes];
}

@end

@interface iTermCollapsingSplitView() <iTermDragHandleViewDelegate>
@end

@implementation iTermCollapsingSplitView {
    NSMutableArray *_items;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _items = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_items release];
    [super dealloc];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)addItem:(NSView<iTermCollapsingSplitViewItem> *)item {
    [_items addObject:item];
    [self update];
}

- (void)removeItem:(NSView<iTermCollapsingSplitViewItem> *)item {
    [_items removeObject:item];
    [self update];
}

- (CGFloat)minimumHeightOfItems:(NSArray *)items {
    CGFloat height = 0;
    for (NSView<iTermCollapsingSplitViewItem> *item in items) {
        height += item.minimumHeight;
    }
    return height;
}

- (CGFloat)heightOfCollapsedItem {
    return 23;
}

- (CGFloat)heightOfItems:(NSArray *)items {
    CGFloat height = 0;
    for (NSView<iTermCollapsingSplitViewItem> *item in items) {
        height += item.frame.size.height;
    }
    return height;
}

- (CGFloat)dividerThickness {
    return 1.0;
}


- (void)update {
    [self updateForHeight:self.frame.size.height];
}

- (void)updateForHeight:(CGFloat)height {
    NSLog(@"XXX begin update %@", @(height));
    NSMutableArray *openItems = [[_items mutableCopy] autorelease];
    NSMutableArray *collapsedItems = [NSMutableArray array];

    for (NSView<iTermCollapsingSplitViewItem> *item in _items) {
        NSRect frame = item.frame;
        frame.size.width = self.frame.size.width;
        item.tempFrame = frame;

    }

    CGFloat availableHeight = height;
    while (openItems.count > 0 &&
           ([self minimumHeightOfItems:openItems] +
            MAX(openItems.count - 1, 0) * self.dividerThickness +
            [self heightOfCollapsedItem] * collapsedItems.count) > availableHeight) {
        [collapsedItems addObject:[openItems lastObject]];
        [openItems removeLastObject];
    }

    CGFloat beforeSize = [self heightOfItems:openItems];
    CGFloat numberOfDividers = openItems.count - 1;
    if (collapsedItems.count == 0 && beforeSize > 0) {
//        NSLog(@"XXX no collapsed items");
        // Everything fits, so try to keep sizes in proportion to their current sizes.
        CGFloat growthCoefficient = (availableHeight - numberOfDividers * self.dividerThickness) / beforeSize;

//        NSLog(@"XXX begin rescaling");
        // Try to scale all views up to first the current size.
        CGFloat totalHeight = 0;
        for (NSView<iTermCollapsingSplitViewItem> *item in openItems) {
            NSRect frame = item.tempFrame;
            frame.size.height = ceil(frame.size.height * growthCoefficient);
            item.tempFrame = frame;
            totalHeight += frame.size.height;
        }

//        NSLog(@"XXX done rescaling. Adjust pixels.");
        // Take off a pixel here or there as needed, being careful not to make any item too short.
        totalHeight += numberOfDividers * self.dividerThickness;
        while (totalHeight > availableHeight) {
            for (NSView<iTermCollapsingSplitViewItem> *item in openItems) {
                NSRect frame = item.tempFrame;
                frame.size.height -= 1;
                if (frame.size.height >= item.minimumHeight) {
                    item.tempFrame = frame;
                    totalHeight -= 1;

                    if (totalHeight <= availableHeight) {
                        break;
                    }
                }
            }
        }

        // Fix up Y origins
        NSLog(@"XXX Done rescaling, begin fixing up y origins");
        CGFloat y = 0;
        for (NSView<iTermCollapsingSplitViewItem> *item in openItems) {
            NSRect frame = item.tempFrame;
            frame.origin.y = y;
            item.tempFrame = frame;
            NSLog(@"  Place %@ at %@, height is %@", item.name, @(y), @(frame.size.height));
            y += frame.size.height + self.dividerThickness;
        }
//        NSLog(@"XXX done fixing up y origins");
    } else {
//        NSLog(@"XXX collapsed views present");
        // There are some collapsed views.
        CGFloat usedHeight = 0;
        NSView<iTermCollapsingSplitViewItem> *lastItem = openItems.lastObject;
        for (NSView<iTermCollapsingSplitViewItem> *item in openItems) {
            NSRect frame = item.tempFrame;
            frame.size.height = item.minimumHeight;
            frame.origin.y = usedHeight;
            usedHeight += frame.size.height;
            if (item != lastItem) {
                usedHeight += self.dividerThickness;
            }
            item.tempFrame = frame;
        }

        usedHeight += collapsedItems.count * [self heightOfCollapsedItem];

        // The last open item grows to fill remaining space.
        NSRect frame = lastItem.tempFrame;
        frame.size.height = availableHeight - usedHeight;
        lastItem.tempFrame = frame;
    }


//    NSLog(@"XXX creating dividers.");
    NSMutableArray *desiredSubviews = [NSMutableArray array];
    CGFloat width = self.frame.size.width;
    for (NSView<iTermCollapsingSplitViewItem> *item in openItems) {
        [desiredSubviews addObject:item];
        if (item != openItems.lastObject) {
            NSRect frame = NSMakeRect(0, NSMaxY(item.tempFrame), width, self.dividerThickness);
            iTermDragHandleView *divider = [[iTermDragHandleView alloc] initWithFrame:frame];
            divider.vertical = NO;
            divider.delegate = self;
            divider.color = _dividerColor;
            [desiredSubviews addObject:divider];
        }
    }

//    NSLog(@"XXX Adding collapsed views");
    CGFloat y = NSMaxY([[desiredSubviews lastObject] tempFrame]);
    for (NSView<iTermCollapsingSplitViewItem> *item in collapsedItems) {
        NSRect frame = NSMakeRect(0, y, width, [self heightOfCollapsedItem]);
        iTermCollapsedItemView *placeholder =
            [[[iTermCollapsedItemView alloc] initWithFrame:frame name:item.name] autorelease];
//        placeholder.delegate = self;
        [desiredSubviews addObject:placeholder];
        y += frame.size.height;
    }

//    NSLog(@"XXX replacing if needed");

    if (self.subviews.count != desiredSubviews.count) {
        [self replaceSubviewsWith:desiredSubviews];
        return;
    } else {
        for (int i = 0; i < self.subviews.count; i++) {
            NSView *actual = self.subviews[i];
            NSView *desired = desiredSubviews[i];

            if ([actual isKindOfClass:[iTermCollapsedItemView class]]) {
                if ([desired isKindOfClass:[iTermCollapsedItemView class]]) {
                    if (![actual isEqual:desired]) {
                        [self replaceSubviewsWith:desiredSubviews];
                        return;
                    }
                } else {
                    [self replaceSubviewsWith:desiredSubviews];
                    return;
                }
            } else if ([actual isKindOfClass:[iTermDragHandleView class]]) {
                if (![desired isKindOfClass:[iTermDragHandleView class]]) {
                    [self replaceSubviewsWith:desiredSubviews];
                    return;
                } else {
                    actual.frame = desired.frame;
                }
            } else if (actual != desired) {
                [self replaceSubviewsWith:desiredSubviews];
                return;
            }
        }
    }

    [self setFramesOfSubviews:self.subviews from:desiredSubviews];

    [self logSubviews];

    [self setNeedsDisplay:YES];
}

- (void)setFramesOfSubviews:(NSArray *)subviews from:(NSArray *)desiredViews {
    for (int i = 0; i < subviews.count; i++) {
        NSView *subview = subviews[i];
        if ([subview conformsToProtocol:@protocol(iTermCollapsingSplitViewItem)]) {
            NSView<iTermCollapsingSplitViewItem> *desiredItem = desiredViews[i];
            NSLog(@"Set frame of %@ to %@", subview, NSStringFromRect(desiredItem.tempFrame));
            subview.frame = desiredItem.tempFrame;
        } else {
            subview.frame = [desiredViews[i] frame];
        }
    }
}

- (void)logSubviews {
    NSLog(@"---");
    for (NSView *view in self.subviews) {
        NSString *name;
        if ([view respondsToSelector:@selector(name)]) {
            name = [view name];
        } else {
            name = [[view class] description];
        }
        NSLog(@"%@ y=%@ height=%@", name, @(view.frame.origin.y), @(view.frame.size.height));
    }
}

- (void)replaceSubviewsWith:(NSArray *)newViews {
    while (self.subviews.count) {
        [[[self.subviews.firstObject retain] autorelease] removeFromSuperview];
    }
    for (id view in newViews) {
        if ([view conformsToProtocol:@protocol(iTermCollapsingSplitViewItem)]) {
            NSView<iTermCollapsingSplitViewItem> *theView = view;
            theView.frame = theView.tempFrame;
        }
        [self addSubview:view];
    }
//    NSLog(@"XXX replacement done. Subviews are:");
    NSLog(@"Replaced subviews");
    [self logSubviews];
}

- (void)setDividerColor:(NSColor *)dividerColor {
    [_dividerColor autorelease];
    _dividerColor = [dividerColor retain];
    for (iTermDragHandleView *view in self.subviews) {
        if ([view isKindOfClass:[iTermDragHandleView class]]) {
            view.color = dividerColor;
        }
    }
    [self setNeedsDisplay:YES];
}

#pragma mark - iTermDragHandleViewDelegate

- (CGFloat)dragHandleView:(iTermDragHandleView *)dragHandle didMoveBy:(CGFloat)delta {
    NSView<iTermCollapsingSplitViewItem> *precedingItem = nil;
    NSView<iTermCollapsingSplitViewItem> *succeedingItem = nil;
    BOOL found = NO;
    for (id view in self.subviews) {
        if ([view conformsToProtocol:@protocol(iTermCollapsingSplitViewItem)]) {
            if (found) {
                succeedingItem = view;
                break;
            } else {
                precedingItem = view;
            }
        } else if (view == dragHandle) {
            found = YES;
        }
    }

    CGFloat allowed = 0;
    if (precedingItem && succeedingItem) {
        if (delta < 0) {
            // Moving down
            CGFloat max = succeedingItem.frame.size.height - succeedingItem.minimumHeight;
            allowed = -MIN(-delta, max);
        } else {
            // Moving up
            CGFloat max = precedingItem.frame.size.height - precedingItem.minimumHeight;
            allowed = MIN(delta, max);
        }
    }

    NSRect frame = precedingItem.frame;
    frame.size.height -= allowed;
    precedingItem.frame = frame;

    frame = dragHandle.frame;
    frame.origin.y -= allowed;
    dragHandle.frame = frame;

    frame = succeedingItem.frame;
    frame.origin.y -= allowed;
    frame.size.height += allowed;
    succeedingItem.frame = frame;

    return allowed;
}

- (void)setFrameSize:(NSSize)newSize {
    if (newSize.width == 0) {
        NSLog(@"WTF");
    }
    [super setFrameSize:newSize];
}

@end
