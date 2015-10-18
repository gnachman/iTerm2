#import "CPKColorWell.h"
#import "CPKControlsView.h"
#import "CPKPopover.h"
#import "NSObject+CPK.h"

@protocol CPKColorWellViewDelegate
@property(nonatomic, readonly) void (^willOpenPopover)();
@property(nonatomic, readonly) void (^willClosePopover)();

- (NSRect)presentationRect;
- (NSView *)presentingView;
- (BOOL)isContinuous;
- (void)colorChangedByDrag:(NSColor *)color;
@end

/** This really should be an NSCell. It provides the implementation of the CPKColorWell. */
@interface CPKColorWellView : CPKSwatchView

/** Block invoked when the user changes the color. Only called for continuous controls. */
@property(nonatomic, copy) void (^colorDidChange)(NSColor *);

/** User can adjust alpha value. */
@property(nonatomic, assign) BOOL alphaAllowed;

/** Color well is disabled? */
@property(nonatomic, assign) BOOL disabled;

@property(nonatomic, weak) id<CPKColorWellViewDelegate> delegate;

@end

@interface CPKColorWellView() <NSDraggingDestination, NSDraggingSource, NSPopoverDelegate>
@property(nonatomic) BOOL open;
@property(nonatomic) CPKPopover *popover;
@property(nonatomic, copy) void (^willClosePopover)(NSColor *);
@property(nonatomic, weak) NSView *savedPresentingView;
@property(nonatomic) NSRect savedPresentationRect;

// The most recently selected color from the picker. Differs from self.color if
// the control is not continuous (self.color is the swatch color).
@property(nonatomic) NSColor *selectedColor;
@end

@interface CPKColorWell() <CPKColorWellViewDelegate>
@end

@implementation CPKColorWellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self colorWellViewCommonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self colorWellViewCommonInit];
    }
    return self;
}

- (void)colorWellViewCommonInit {
    [self registerForDraggedTypes:@[ NSPasteboardTypeColor ]];
}

- (void)awakeFromNib {
    self.cornerRadius = 3;
    self.open = NO;
}

// Use mouseDown so this will work in a NSTableView.
- (void)mouseDown:(NSEvent *)theEvent {
    if (!self.delegate.isContinuous && theEvent.clickCount == 1) {
        [self openPopOver];
    }
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (self.delegate.isContinuous && theEvent.clickCount == 1) {
        [self openPopOver];
    }
}

- (void)openPopOver {
    if (!_disabled && !self.open) {
        [self openPopOverRelativeToRect:_delegate.presentationRect
                                 ofView:_delegate.presentingView];
    }
}

- (void)mouseDragged:(NSEvent *)theEvent {
    NSColor *color = self.selectedColor ?: [NSColor clearColor];
    NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:color];

    dragItem.imageComponentsProvider = ^NSArray<NSDraggingImageComponent *> *(void) {
        NSDraggingImageComponent *imageComponent =
            [NSDraggingImageComponent draggingImageComponentWithKey:NSDraggingImageComponentIconKey];

        NSImage *snapshot = [[NSImage alloc] initWithSize:self.frame.size];
        [snapshot lockFocus];
        [self drawRect:self.bounds];
        [snapshot unlockFocus];

        imageComponent.contents = snapshot;
        imageComponent.frame = self.bounds;

        return @[ imageComponent ];
    };
    [self beginDraggingSessionWithItems:@[ dragItem ]
                                  event:theEvent
                                 source:self];
}

#pragma mark - NSDraggingDestination

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    __block NSDragOperation operation = NSDragOperationNone;
    [sender enumerateDraggingItemsWithOptions:0
                                      forView:self
                                      classes:@[ [NSColor class] ]
                                searchOptions:@{}
                                   usingBlock:^(NSDraggingItem * _Nonnull draggingItem, NSInteger idx, BOOL * _Nonnull stop) {
                                       NSColor *color = draggingItem.item;
                                       if (color) {
                                           operation = NSDragOperationGeneric;
                                           *stop = YES;
                                       }
                                   }];
    return operation;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    __block BOOL ok = NO;
    [sender enumerateDraggingItemsWithOptions:0
                                      forView:self
                                      classes:@[ [NSColor class] ]
                                searchOptions:@{}
                                   usingBlock:^(NSDraggingItem * _Nonnull draggingItem, NSInteger idx, BOOL * _Nonnull stop) {
                                       NSColor *color = draggingItem.item;
                                       if (color) {
                                           self.popover.selectedColor = color;
                                           self.selectedColor = color;
                                           [self.delegate colorChangedByDrag:color];

                                           ok = YES;
                                           *stop = YES;
                                       }
                                   }];
    return ok;
}


#pragma mark - NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationGeneric;
}

- (void)colorPanelColorDidChange:(id)sender {
    [self.delegate colorChangedByDrag:[sender color]];
}

- (void)useColorPicker:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kCPKUseSystemColorPicker];
    [[NSColorPanel sharedColorPanel] close];
    [[NSColorPanel sharedColorPanel] setAccessoryView:nil];
    if (self.savedPresentingView.window) {
        [self openPopOverRelativeToRect:self.savedPresentationRect ofView:self.savedPresentingView];
    }
}

- (void)showSystemColorPicker {
    NSColorPanel *colorPanel = [NSColorPanel sharedColorPanel];
    
    // Add an accessory view to use ColorPicker.
    NSImage *image = [self cpk_imageNamed:@"ActiveEscapeHatch"];
    NSRect frame;
    frame.origin = NSZeroPoint;
    frame.size = image.size;
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.bordered = NO;
    button.image = image;
    button.imagePosition = NSImageOnly;
    [button setTarget:self];
    [button setAction:@selector(useColorPicker:)];
    colorPanel.accessoryView = button;
    
    [colorPanel setTarget:self];
    [colorPanel setAction:@selector(colorPanelColorDidChange:)];
    [colorPanel orderFront:nil];
    colorPanel.showsAlpha = self.alphaAllowed;
    colorPanel.color = self.selectedColor;
}

- (void)openPopOverRelativeToRect:(NSRect)presentationRect ofView:(NSView *)presentingView {
    self.savedPresentationRect = presentationRect;
    self.savedPresentingView = presentingView;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kCPKUseSystemColorPicker]) {
        [self showSystemColorPicker];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    self.selectedColor = self.color;
    self.popover =
        [CPKPopover presentRelativeToRect:presentationRect
                                   ofView:presentingView
                            preferredEdge:NSRectEdgeMinY
                             initialColor:self.color
                             alphaAllowed:self.alphaAllowed
                       selectionDidChange:^(NSColor *color) {
                           if (!color) {
                               [weakSelf.popover close];
                               [self showSystemColorPicker];
                               return;
                           }
                           weakSelf.selectedColor = color;
                           if (weakSelf.delegate.isContinuous) {
                               weakSelf.color = color;
                               if (weakSelf.colorDidChange) {
                                   weakSelf.colorDidChange(color);
                               }
                           }
                           [weakSelf setNeedsDisplay:YES];
                       }];
    self.open = YES;
    self.popover.willClose = ^() {
        if (weakSelf.willClosePopover) {
            weakSelf.willClosePopover(weakSelf.color);
        }
        weakSelf.color = weakSelf.selectedColor;
        weakSelf.open = NO;
        weakSelf.popover = nil;
    };
    if (weakSelf.delegate.willOpenPopover) {
        weakSelf.delegate.willOpenPopover();
    }
}

- (void)setOpen:(BOOL)open {
    _open = open;
    [self updateBorderColor];
}

- (void)updateBorderColor {
    if (self.disabled) {
        self.borderColor = [NSColor grayColor];
    } else if (self.open) {
        self.borderColor = [NSColor lightGrayColor];
    } else {
        self.borderColor = [NSColor darkGrayColor];
    }
    [self setNeedsDisplay:YES];
}

- (void)setDisabled:(BOOL)disabled {
    _disabled = disabled;
    [self updateBorderColor];
    if (disabled && self.popover) {
        [self.popover performClose:self];
    }
}

@end

@implementation CPKColorWell {
  CPKColorWellView *_view;
  BOOL _continuous;
}

// This is the path taken when created programatically.
- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    [self load];
  }
  return self;
}

// This is the path taken when loaded from a nib.
- (void)awakeFromNib {
  [self load];
}

- (void)load {
    if (_view) {
        return;
    }

    _continuous = YES;
    _view = [[CPKColorWellView alloc] initWithFrame:self.bounds];
    _view.delegate = self;
    [self addSubview:_view];
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.autoresizesSubviews = YES;
    _view.alphaAllowed = _alphaAllowed;
    __weak __typeof(self) weakSelf = self;
    _view.colorDidChange = ^(NSColor *color) {
        [weakSelf sendAction:weakSelf.action to:weakSelf.target];
    };
    _view.willClosePopover = ^(NSColor *color) {
        if (!weakSelf.continuous) {
            [weakSelf sendAction:weakSelf.action to:weakSelf.target];
        }
        if (weakSelf.willClosePopover) {
            weakSelf.willClosePopover();
        }
    };
}

- (NSColor *)color {
  return _view.selectedColor;
}

- (void)setColor:(NSColor *)color {
    _view.color = color;
    _view.selectedColor = color;
}

- (void)setAlphaAllowed:(BOOL)alphaAllowed {
  _alphaAllowed = alphaAllowed;
  _view.alphaAllowed = alphaAllowed;
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  _view.disabled = !enabled;
}

- (void)setContinuous:(BOOL)continuous {
  _continuous = continuous;
}

- (BOOL)isContinuous {
  return _continuous;
}

- (NSRect)presentationRect {
  return self.bounds;
}

- (NSView *)presentingView {
  return self;
}

- (void)colorChangedByDrag:(NSColor *)color {
    [self setColor:color];
    [self sendAction:self.action to:self.target];
}

@end
