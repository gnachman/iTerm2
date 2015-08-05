//
//  iTermTwoColorWellsCell.m
//  iTerm2
//
//  Created by George Nachman on 6/5/15.
//
//

#import "iTermTwoColorWellsCell.h"

#import "iTermNoColorAccessoryButton.h"

@implementation iTermTwoColorWellsCell {
    NSRect _textLabelFrame;
    NSRect _backgroundLabelFrame;
    NSRect _firstWellFrame;
    NSRect _secondWellFrame;
    int _lastHitWell;
}

- (NSRect)drawingRectForBounds:(NSRect)theRect {
    return theRect;
}

- (NSColor *)cellTextColor {
    if ([self isHighlighted] && self.controlView.window.isKeyWindow) {
        return [NSColor whiteColor];
    } else {
        return [NSColor blackColor];
    }
}

- (NSCellHitResult)hitTestForEvent:(NSEvent *)event
                            inRect:(NSRect)cellFrame
                            ofView:(NSView *)controlView {
     [self layoutComponentsInFrame:cellFrame];
     NSPoint point = [controlView convertPoint:event.locationInWindow fromView:nil];
     NSCellHitResult result = 0;
     if (NSPointInRect(point, cellFrame)) {
         result |= NSCellHitTrackableArea;
     }
     if (NSPointInRect(point, _firstWellFrame)) {
         _lastHitWell = 0;
         result |= NSCellHitContentArea;
     } else if (NSPointInRect(point, _secondWellFrame)) {
         _lastHitWell = 1;
         result |= NSCellHitContentArea;
     } else {
         _lastHitWell = -1;
     }
     return result;
                            }

- (BOOL)trackMouse:(NSEvent *)event
            inRect:(NSRect)cellFrame
            ofView:(NSView *)controlView
      untilMouseUp:(BOOL)flag {
          if ([event type] != NSLeftMouseDown) {
              // We only care about mouse down and will block until mouse up.
              return YES;
          }

          // Check if the button was hit.
          NSCellHitResult hitResult = [self hitTestForEvent:event
                                                     inRect:cellFrame
                                                     ofView:controlView];
          static const NSCellHitResult hitOnWellResult = (NSCellHitTrackableArea | NSCellHitContentArea);
          BOOL isHitOnWell = (hitResult == hitOnWellResult);
          if (!isHitOnWell) {
              return YES;
          }

          // Grab all events until a mouse up event.
          const NSUInteger theMask = (NSLeftMouseUpMask |
                                      NSLeftMouseDraggedMask |
                                      NSMouseEnteredMask |
                                      NSMouseExitedMask);
          NSEvent *nextEvent = nil;
          do {
              nextEvent = [[controlView window] nextEventMatchingMask:theMask];
              hitResult = [self hitTestForEvent:nextEvent
                                         inRect:cellFrame
                                         ofView:controlView];

              isHitOnWell = hitResult == hitOnWellResult;

              if (!isHitOnWell) {
                  [NSApp sendEvent:nextEvent];
              }
          } while ([nextEvent type] != NSLeftMouseUp);
          // Perform click only if the button was hit.
          if (isHitOnWell) {
              // Use dispatch async because we want this to run after tableViewSelectionDidChange:
              [self retain];
              dispatch_async(dispatch_get_main_queue(), ^{
                                 [self openColorPickerForWell:_lastHitWell];
                                 [self release];
                             });
          }

          return YES;
      }

- (void)drawColorWellWithSelectedColor:(NSColor *)color inFrame:(NSRect)rect highlight:(BOOL)highlight {
    if (color) {
        [color set];
        NSRectFill(rect);
    } else {
        [[NSColor whiteColor] set];
        NSRectFill(rect);

        NSBezierPath *path = [[[NSBezierPath alloc] init] autorelease];
        [path moveToPoint:rect.origin];
        [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
        [[NSColor grayColor] set];
        [path stroke];
    }

    if (highlight) {
        [[NSColor whiteColor] set];
    } else {
        [[NSColor blackColor] set];
    }
    NSFrameRect(rect);
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    [context saveGraphicsState];
    NSRectClip(cellFrame);

    [self layoutComponentsInFrame:cellFrame];
    [[self attributedStringForLabel:[self textLabel]] drawInRect:_textLabelFrame];
    [[self attributedStringForLabel:[self backgroundLabel]] drawInRect:_backgroundLabelFrame];
    [self drawColorWellWithSelectedColor:self.textColor
                                 inFrame:_firstWellFrame
                               highlight:[self isHighlighted] && [self currentWell] == 0];
    [self drawColorWellWithSelectedColor:self.backgroundColor
                                 inFrame:_secondWellFrame
                               highlight:[self isHighlighted] && [self currentWell] == 1];

    [context restoreGraphicsState];
}

- (NSString *)textLabel {
    return @"Text";
}

- (NSString *)backgroundLabel {
    return @"Background";
}

- (NSAttributedString *)attributedStringForLabel:(NSString *)label {
  NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:13],
                     NSForegroundColorAttributeName: [self cellTextColor] };
  NSAttributedString *string = [[[NSAttributedString alloc] initWithString:label
                                                                attributes:attributes] autorelease];
  return string;
}

- (NSRect)rectForAttributedString:(NSAttributedString *)attributedString
                              atX:(CGFloat)x
                      inCellFrame:(NSRect)cellFrame {
                          NSSize size = [attributedString size];

                          NSRect rect = cellFrame;
                          rect.origin.x += x;
                          rect.origin.y += cellFrame.size.height;
                          rect.origin.y -= size.height;
                          rect.size.width = size.width;
                          rect.size.height = size.height;
                          return rect;
                      }

- (NSRect)rectForWellAtX:(CGFloat)x inCellFrame:(NSRect)cellFrame {
    static const CGFloat kWellWidth = 30;
    NSRect rect = cellFrame;
    rect.origin.x += x;
    if (self.controlView.window.backingScaleFactor <= 1) {
        rect.origin.y += 2;
        rect.size.height -= 4;
    } else {
        rect.origin.y += 1.5;  // This centers it properly on Retina
        rect.size.height -= 3.5;
    }
    rect.size.width = kWellWidth;
    return rect;
}

- (void)layoutComponentsInFrame:(NSRect)cellFrame {
    static const CGFloat kMargin = 4;
    static const CGFloat kSpaceBetweenTextAndBackground = 8;

    _textLabelFrame = [self rectForAttributedString:[self attributedStringForLabel:[self textLabel]]
                                                atX:0
                                        inCellFrame:cellFrame];
    _firstWellFrame = [self rectForWellAtX:NSMaxX(_textLabelFrame) - cellFrame.origin.x + kMargin
                               inCellFrame:cellFrame];

    _backgroundLabelFrame = [self rectForAttributedString:[self attributedStringForLabel:[self backgroundLabel]]
                                                      atX:kSpaceBetweenTextAndBackground + NSMaxX(_firstWellFrame) + kMargin - cellFrame.origin.x
                                              inCellFrame:cellFrame];
    _secondWellFrame = [self rectForWellAtX:NSMaxX(_backgroundLabelFrame) - cellFrame.origin.x + kMargin
                                inCellFrame:cellFrame];
}

- (NSView *)accessoryView {
    return [[[iTermNoColorAccessoryButton alloc] init] autorelease];
}

- (void)openColorPickerForWell:(int)wellNumber {
    [[NSApplication sharedApplication] orderFrontColorPanel:nil];
    [[NSColorPanel sharedColorPanel] setAccessoryView:[self accessoryView]];
    id firstResponder = self.controlView.window.firstResponder;
    if ([firstResponder respondsToSelector:@selector(twoColorWellsCellDidOpenPickerForWellNumber:)]) {
        [firstResponder twoColorWellsCellDidOpenPickerForWellNumber:wellNumber];
    }
}

- (int)currentWell {
    id firstResponder = self.controlView.window.firstResponder;
    if ([firstResponder respondsToSelector:@selector(currentWellForCell)]) {
        NSNumber *n = [firstResponder currentWellForCell];
        if (n) {
            return [n intValue];
        }
    }
    return -1;
}

@end
