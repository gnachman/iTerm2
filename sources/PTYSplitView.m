//
//  PTYSplitView.m
//  iTerm
//
//  Created by George Nachman on 12/10/11.
//

#import "PTYSplitView.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "NSAppearance+iTerm.h"
#import "NSColor+iTerm.h"
#import "PTYWindow.h"

@implementation PTYSplitViewDividerInfo

- (instancetype)initWithFrame:(NSRect)frame vertical:(BOOL)vertical {
    self = [super init];
    if (self) {
        _frame = frame;
        _isVertical = vertical;
    }
    return self;
}

- (NSString *)description {
    return NSStringFromRect(_frame);
}

- (NSComparisonResult)compare:(PTYSplitViewDividerInfo *)other {
    if (_isVertical) {
        return [@(_frame.origin.x) compare:@(other.frame.origin.x)];
    }
    return [@(_frame.origin.y) compare:@(other.frame.origin.y)];
}

@end

@implementation PTYSplitView {
    NSString *_stringUniqueIdentifier;
    BOOL _dead;  // inside superclass's dealloc?
}

@dynamic delegate;

- (instancetype)initWithFrame:(NSRect)frame uniqueIdentifier:(NSString *)identifier {
    self = [super initWithFrame:frame];
    if (self) {
        _stringUniqueIdentifier = identifier ?: [[NSUUID UUID] UUIDString];
    }
    return self;
}

- (instancetype)initWithUniqueIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _stringUniqueIdentifier = identifier ?: [[NSUUID UUID] UUIDString];
    }
    return self;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _stringUniqueIdentifier = [[NSUUID UUID] UUIDString];
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _stringUniqueIdentifier = [[NSUUID UUID] UUIDString];
    }
    return self;
}

- (void)dealloc {
    _dead = YES;
}

- (NSColor *)dividerColor {
    NSString *customString = [iTermAdvancedSettingsModel splitPaneColor];
    if ([customString hasPrefix:@"#"]) {
        NSColor *custom = [NSColor colorFromHexString:customString];
        if (custom) {
            return custom;
        }
    }
    NSColor *color = self.window.ptyWindow.it_terminalWindowDecorationControlColor;
    return color;
}

- (NSString *)description
{
    NSMutableString *d = [NSMutableString stringWithString:@"<PTYSplitView "];
    [d appendFormat:@"<%@:%p frame:%@ splitter:%@ [",
        [self class],
        self,
        [NSValue valueWithRect:[self frame]],
        [self isVertical] ? @"|" : @"--"];
    for (NSView *view in [self subviews]) {
        [d appendFormat:@" (%@)", [view description]];
    }
    [d appendFormat:@">"];
    return d;
}

// NSSplitView, that paragon of quality, does not redraw itself properly
// on 10.14 (and, who knows, maybe earlier versions) unless you subclass
// drawRect.
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
}

- (void)mouseDown:(NSEvent *)theEvent
{
    if (self.subviews.count == 0) {
        return;
    }
    // First, find the splitter that was clicked on. It will be the one closest
    // to the mouse. The OS seems to give a bit of wiggle room so it's not
    // necessary exactly under the mouse.
    int clickedOnSplitterIndex = -1;
    NSArray *subviews = [self subviews];
    NSPoint locationInWindow = [theEvent locationInWindow];
    locationInWindow.y--;
    NSPoint locationInView = [self convertPoint:locationInWindow fromView:nil];
    int x = 0;
    int y = 0;
    int bestDistance = -1;
    const BOOL isVertical = [self isVertical];
    if (isVertical) {
        int mouseX = locationInView.x;
        x = 0;
        int bestX = 0;
        for (int i = 0; i < subviews.count; i++) {
            x += [[subviews objectAtIndex:i] frame].size.width;
            if (bestDistance < 0 || abs(x - mouseX) < bestDistance) {
                bestDistance = abs(x - mouseX);
                clickedOnSplitterIndex = i;
                bestX = x;
            }
            x += [self dividerThickness];
        }
        x = bestX;
    } else {
        int mouseY = locationInView.y;
        int bestY = 0;
        y = 0;
        for (int i = 0; i < subviews.count - 1; i++) {
            float subviewHeight = [[subviews objectAtIndex:i] frame].size.height;
            y += subviewHeight;
            if (bestDistance < 0 || abs(y - mouseY) < bestDistance) {
                bestDistance = abs(y - mouseY);
                clickedOnSplitterIndex = i;
                bestY = y;
            }
            y += [self dividerThickness];
        }
        y = bestY;
    }

    // mouseDown blocks and lets the user drag things around.
    if (clickedOnSplitterIndex < 0) {
        // You don't seem to have clicked on a splitter.
        DLog(@"Click in PTYSplitView was not on splitter");
        return;
    }
    [[self delegate] splitView:self draggingWillBeginOfSplit:clickedOnSplitterIndex];

    [super mouseDown:theEvent];

    // See how much the view after the splitter moved
    NSSize changePx = NSZeroSize;
    NSRect frame = [[subviews objectAtIndex:clickedOnSplitterIndex] frame];
    if (isVertical) {
        changePx.width = (frame.origin.x + frame.size.width) - x;
    } else {
        changePx.height = (frame.origin.y + frame.size.height) - y;
    }

    // Run our delegate method.
    [[self delegate] splitView:self
         draggingDidEndOfSplit:clickedOnSplitterIndex
                        pixels:changePx];
}

- (void)didAddSubview:(NSView *)subview {
    [super didAddSubview:subview];
    [self.delegate splitViewDidChangeSubviews:self];
    [self performSelector:@selector(forceRedraw) withObject:nil afterDelay:0];
}

- (void)willRemoveSubview:(NSView *)subview {
    if (_dead) {
        // Was called from within superclass's -dealloc, and trying to construct a weak reference
        // will crash.
        return;
    }
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf.delegate splitViewDidChangeSubviews:self];
    });
    [super willRemoveSubview:subview];
    [self performSelector:@selector(forceRedraw) withObject:nil afterDelay:0];
}

- (void)forceRedraw {
    [self setNeedsDisplay:YES];
}

- (void)setFrame:(NSRect)frame {
    DLog(@"%@: setFrame:%@\n%@", self, NSStringFromRect(frame), [NSThread callStackSymbols]);
    DLog(@"superview's frame is %@", NSStringFromRect([[self superview] frame]));
    if (NSEqualRects(self.frame, frame)) {
        DLog(@"frame isn't changing, return.");
        return;
    }
    [super setFrame:frame];
}

- (void)setFrameSize:(NSSize)newSize {
    DLog(@"%@: setFrameSize:%@\n%@", self, NSStringFromSize(newSize), [NSThread callStackSymbols]);
    [super setFrameSize:newSize];
}

- (void)setFrameOrigin:(NSPoint)newOrigin {
    DLog(@"%@: setFrameOrigin:%@\n%@", self, NSStringFromPoint(newOrigin), [NSThread callStackSymbols]);
    [super setFrameOrigin:newOrigin];
}

- (NSArray<PTYSplitViewDividerInfo *> *)transitiveDividerLocationsVertical:(BOOL)vertical {
    return [self transitiveDividerLocationsVertical:vertical root:self];
}

- (NSArray<PTYSplitViewDividerInfo *> *)transitiveDividerLocationsVertical:(BOOL)vertical
                                                                      root:(PTYSplitView *)root {
    const NSPoint originPoint = [root convertRect:self.bounds fromView:self].origin;

    NSMutableArray<PTYSplitViewDividerInfo *> *result = [NSMutableArray array];
    CGFloat offset = vertical ? originPoint.x : originPoint.y;
    const CGFloat dividerThickness = self.dividerThickness;
    const NSInteger count = self.subviews.count;
    for (NSInteger i = 0; i < count; i++) {
        const NSSize size = self.subviews[i].frame.size;
        offset += vertical ? size.width : size.height;
        if (i + 1 < count && self.isVertical == vertical) {
            NSRect dividerFrame;
            if (vertical) {
                dividerFrame = NSMakeRect(offset, originPoint.y, dividerThickness, self.bounds.size.height);
            } else {
                dividerFrame = NSMakeRect(originPoint.x, offset, self.bounds.size.width, dividerThickness);
            }
            PTYSplitViewDividerInfo *info = [[PTYSplitViewDividerInfo alloc] initWithFrame:dividerFrame
                                                                                  vertical:vertical];
            [result addObject:info];
        }
        __kindof NSView *subview = self.subviews[i];
        if ([subview isKindOfClass:[PTYSplitView class]]) {
            PTYSplitView *childSplit = subview;
            [result addObjectsFromArray:[childSplit transitiveDividerLocationsVertical:vertical
                                                                                  root:root]];
        }
        offset += dividerThickness;
    }
    return [result sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - iTermUniquelyIdentifiable

- (NSString *)stringUniqueIdentifier {
    return _stringUniqueIdentifier;
}

@end


