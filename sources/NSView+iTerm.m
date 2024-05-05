//
//  NSView+iTerm.m
//  iTerm
//
//  Created by George Nachman on 3/15/14.
//
//

#import "NSView+iTerm.h"
#import "DebugLogging.h"
#import "iTermApplication.h"
#import "iTermTextPopoverViewController.h"
#import "NSObject+iTerm.h"
#import "NSWindow+iTerm.h"

static NSInteger gTakingSnapshot;

@implementation NSView (iTerm)

+ (BOOL)iterm_takingSnapshot {
    return gTakingSnapshot > 0;
}

+ (NSView *)viewAtScreenCoordinate:(NSPoint)point {
    const NSRect mouseRect = {
        .origin = point,
        .size = NSZeroSize
    };
    NSArray<NSWindow *> *frontToBackWindows = [[iTermApplication sharedApplication] orderedWindowsPlusVisibleHotkeyPanels];
    for (NSWindow *window in frontToBackWindows) {
        if (!window.isOnActiveSpace) {
            continue;
        }
        if (!window.isVisible) {
            continue;
        }
        NSPoint pointInWindow = [window convertRectFromScreen:mouseRect].origin;
        if ([window isTerminalWindow]) {
            DLog(@"Consider window %@", window.title);
            NSView *view = [window.contentView hitTest:pointInWindow];
            if (view) {
                return view;
            } else {
                DLog(@"%@ failed hit test", window.title);
            }
        }
    }
    return nil;
}

- (NSImage *)snapshot {
    return [self snapshotOfRect:self.bounds];
}

- (NSImage *)snapshotOfRect:(NSRect)rect {
    gTakingSnapshot += 1;

    NSBitmapImageRep *rep = [self bitmapImageRepForCachingDisplayInRect:rect];
    [self cacheDisplayInRect:self.bounds toBitmapImageRep:rep];
    NSImage *image = [[NSImage alloc] initWithSize:rect.size];
    [image addRepresentation:rep];

    gTakingSnapshot -= 1;
    return image;
}

- (void)insertSubview:(NSView *)subview atIndex:(NSInteger)index {
    NSArray *subviews = [self subviews];
    if (subviews.count == 0) {
        [self addSubview:subview];
        return;
    }
    if (index == 0) {
        [self addSubview:subview positioned:NSWindowBelow relativeTo:subviews[0]];
    } else {
        [self addSubview:subview positioned:NSWindowAbove relativeTo:subviews[index - 1]];
    }
}

- (void)swapSubview:(NSView *)subview1 withSubview:(NSView *)subview2 {
    NSArray *subviews = [self subviews];
    NSUInteger index1 = [subviews indexOfObject:subview1];
    NSUInteger index2 = [subviews indexOfObject:subview2];
    assert(index1 != index2);
    assert(index1 != NSNotFound);
    assert(index2 != NSNotFound);

    NSRect frame1 = subview1.frame;
    NSRect frame2 = subview2.frame;

    NSView *filler1 = [[NSView alloc] initWithFrame:subview1.frame];
    NSView *filler2 = [[NSView alloc] initWithFrame:subview2.frame];

    [self replaceSubview:subview1 with:filler1];
    [self replaceSubview:subview2 with:filler2];

    subview1.frame = frame2;
    subview2.frame = frame1;

    [self replaceSubview:filler1 with:subview2];
    [self replaceSubview:filler2 with:subview1];
}

+ (iTermDelayedPerform *)animateWithDuration:(NSTimeInterval)duration
                                       delay:(NSTimeInterval)delay
                                  animations:(void (^)(void))animations
                                  completion:(void (^)(BOOL finished))completion {
    iTermDelayedPerform *delayedPerform = [[iTermDelayedPerform alloc] init];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       if (!delayedPerform.canceled) {
                           DLog(@"Run dp %@", delayedPerform);
                           [self animateWithDuration:duration
                                          animations:animations
                                          completion:^(BOOL finished) {
                                              delayedPerform.completed = YES;
                                              completion(finished);
                                          }];
                       } else {
                           completion(NO);
                       }
                   });
    return delayedPerform;
}

+ (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(void (NS_NOESCAPE ^)(void))animations
                 completion:(void (^)(BOOL finished))completion {
   NSAnimationContext *context = [NSAnimationContext currentContext];
   NSTimeInterval savedDuration = [context duration];
   if (duration > 0) {
       [context setDuration:duration];
   }
   animations();
   [context setDuration:savedDuration];

   if (completion) {
       dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                      dispatch_get_main_queue(), ^{
                          completion(YES);
                      });
   }
}

- (void)enumerateHierarchy:(void (NS_NOESCAPE ^)(NSView *))block {
    block(self);
    for (NSView *view in self.subviews) {
        [view enumerateHierarchy:block];
    }
}

- (CGFloat)retinaRound:(CGFloat)value {
    NSWindow *window = self.window;
    if (!window) {
        return round(value);
    }
    CGFloat scale = window.backingScaleFactor;
    if (!scale) {
        scale = [[NSScreen mainScreen] backingScaleFactor];
    }
    if (!scale) {
        scale = 1;
    }
    return round(scale * value) / scale;
}

- (CGFloat)retinaRoundUp:(CGFloat)value {
    NSWindow *window = self.window;
    if (!window) {
        return ceil(value);
    }
    CGFloat scale = window.backingScaleFactor;
    if (!scale) {
        scale = [[NSScreen mainScreen] backingScaleFactor];
    }
    if (!scale) {
        scale = 1;
    }
    return ceil(scale * value) / scale;
}

- (CGRect)retinaRoundRect:(CGRect)rect {
    NSRect result = NSMakeRect([self retinaRound:NSMinX(rect)],
                               [self retinaRound:NSMinY(rect)],
                               [self retinaRoundUp:NSWidth(rect)],
                               [self retinaRoundUp:NSHeight(rect)]);
    return result;
}

- (BOOL)containsDescendant:(NSView *)possibleDescendant {
    for (NSView *subview in self.subviews) {
        if (subview == possibleDescendant || [subview containsDescendant:possibleDescendant]) {
            return YES;
        }
    }
    return NO;
}

- (NSColor *)it_backgroundColorOfEnclosingTerminalIfBackgroundColorViewHidden {
    return [self.superview it_backgroundColorOfEnclosingTerminalIfBackgroundColorViewHidden];
}

- (void)it_showWarning:(NSString *)text {
    [self it_showWarning:text rect:self.bounds];
}

- (void)it_showWarning:(NSString *)text rect:(NSRect)rect {
    iTermTextPopoverViewController *popoverVC = [[iTermTextPopoverViewController alloc] initWithNibName:@"iTermTextPopoverViewController"
                                                                  bundle:[NSBundle bundleForClass:self.class]];
    popoverVC.popover.behavior = NSPopoverBehaviorTransient;
    [popoverVC view];
    popoverVC.textView.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    popoverVC.textView.drawsBackground = NO;
    [popoverVC appendString:text];
    [popoverVC sizeToFit];
    [popoverVC.view it_setAssociatedObject:@YES forKey:iTermDeclineFirstResponderAssociatedObjectKey];
    [popoverVC.popover showRelativeToRect:rect
                                    ofView:self
                             preferredEdge:NSRectEdgeMaxY];
    [self it_setAssociatedObject:popoverVC forKey:@"PopoverWarning"];
}

- (void)it_showWarningWithAttributedString:(NSAttributedString *)text rect:(NSRect)rect {
    iTermTextPopoverViewController *popoverVC = [[iTermTextPopoverViewController alloc] initWithNibName:@"iTermTextPopoverViewController"
                                                                  bundle:[NSBundle bundleForClass:self.class]];
    popoverVC.popover.behavior = NSPopoverBehaviorTransient;
    [popoverVC view];
    popoverVC.textView.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    popoverVC.textView.drawsBackground = NO;
    [popoverVC appendAttributedString:text];
    [popoverVC sizeToFit];
    [popoverVC.view it_setAssociatedObject:@YES forKey:iTermDeclineFirstResponderAssociatedObjectKey];
    [popoverVC.popover showRelativeToRect:rect
                                    ofView:self
                             preferredEdge:NSRectEdgeMaxY];
    [self it_setAssociatedObject:popoverVC forKey:@"PopoverWarning"];
}

- (void)it_removeWarning {
    iTermTextPopoverViewController *vc = [self it_associatedObjectForKey:@"PopoverWarning"];
    if (!vc) {
        return;
    }
    [vc.popover close];
    [self it_setAssociatedObject:nil forKey:@"PopoverWarning"];
}

- (NSPoint)viewPointFromAccessibilityScreenPoint:(NSPoint)stupidScreenPoint {
    const CGFloat flippedY = NSMaxY([NSScreen mainScreen].frame) - stupidScreenPoint.y;
    const NSPoint regularScreenPoint = NSMakePoint(stupidScreenPoint.x, flippedY);
    const NSPoint windowPoint = [self.window convertPointFromScreen:regularScreenPoint];
    const NSPoint viewPoint = [self convertPoint:windowPoint fromView:nil];
    return viewPoint;
}

@end
