//
//  iTermHamburgerButton.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/30/20.
//

#import "iTermHamburgerButton.h"

#import "NSImage+iTerm.h"

@protocol iTermHamburgerButtonCellControl<NSObject>
- (NSMenu *)hamburgerMenu;
@end

@interface iTermHamburgerButtonCell : NSButtonCell
@end

@implementation iTermHamburgerButtonCell

- (BOOL)trackMouse:(NSEvent *)event
            inRect:(NSRect)cellFrame
            ofView:(NSView *)controlView
      untilMouseUp:(BOOL)untilMouseUp {
    if (![controlView conformsToProtocol:@protocol(iTermHamburgerButtonCellControl)]) {
        return [super trackMouse:event inRect:cellFrame ofView:controlView untilMouseUp:untilMouseUp];
    }
    id<iTermHamburgerButtonCellControl> control = (id<iTermHamburgerButtonCellControl>)controlView;
    const NSPoint centerPoint = [controlView convertPoint:NSMakePoint(NSMidX(cellFrame),
                                                                      NSMidY(cellFrame))
                                                   toView:nil];

    NSEvent *fakeEvent = [NSEvent mouseEventWithType:[event type]
                                            location:centerPoint
                                       modifierFlags:[event modifierFlags]
                                           timestamp:[event timestamp]
                                        windowNumber:[event windowNumber]
                                             context:nil
                                         eventNumber:[event eventNumber]
                                          clickCount:[event clickCount]
                                            pressure:[event pressure]];
    [NSMenu popUpContextMenu:[control hamburgerMenu] withEvent:fakeEvent forView:controlView];

    return YES;
}

@end

@interface iTermHamburgerButton()<iTermHamburgerButtonCellControl>
@end

@implementation iTermHamburgerButton

- (instancetype)initWithMenuProvider:(NSMenu *(^)(void))menuProvider {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.cell = [[iTermHamburgerButtonCell alloc] init];
        self.bezelStyle = NSBezelStyleRegularSquare;
        self.bordered = NO;
        self.image = [NSImage it_hamburgerForClass:self.class];
        self.imagePosition = NSImageOnly;
        _menuProvider = [menuProvider copy];
    }
    return self;
}

- (NSMenu *)hamburgerMenu {
    return _menuProvider();
}

@end
