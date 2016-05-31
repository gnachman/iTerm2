//
//  PSMTabBarControl.m
//  PSMTabBarControl
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import "PSMTabBarControl.h"
#import "PSMTabBarCell.h"
#import "PSMOverflowPopUpButton.h"
#import "PSMRolloverButton.h"
#import "PSMTabStyle.h"
#import "PSMYosemiteTabStyle.h"
#import "PSMTabDragAssistant.h"
#import "PTYTask.h"
#import "NSWindow+PSM.h"

NSString *const kPSMModifierChangedNotification = @"kPSMModifierChangedNotification";
NSString *const kPSMTabModifierKey = @"TabModifier";
NSString *const PSMTabDragDidEndNotification = @"PSMTabDragDidEndNotification";
NSString *const PSMTabDragDidBeginNotification = @"PSMTabDragDidBeginNotification";
const CGFloat kPSMTabBarControlHeight = 22;
const CGFloat kSPMTabBarCellInternalXMargin = 6;
const CGFloat kSPMTabBarCellInternalYMargin = 3.5;

const CGFloat kPSMTabBarCellPadding = 4;
const CGFloat kPSMTabBarCellIconPadding = 0;
// fixed size objects
const CGFloat kPSMMinimumTitleWidth = 30;
const CGFloat kPSMTabBarIndicatorWidth = 16.0;
const CGFloat kPSMTabBarIconWidth = 16.0;
const CGFloat kPSMHideAnimationSteps = 2.0;

// Value used in _currentStep to indicate that resizing operation is not in progress
const NSInteger kPSMIsNotBeingResized = -1;

// Value used in _currentStep when a resizing operation has just been started
const NSInteger kPSMStartResizeAnimation = 0;

@interface PSMTabBarControl ()<PSMTabBarControlProtocol>
@end

@implementation PSMTabBarControl {
    // control basics
    NSMutableArray *_cells; // the cells that draw the tabs
    PSMOverflowPopUpButton *_overflowPopUpButton; // for too many tabs
    PSMRolloverButton *_addTabButton;

    // drawing style
    int _resizeAreaCompensation;
    NSTimer *_animationTimer;
    float _animationDelta;

    // vertical tab resizing
    BOOL _resizing;

    // animation for hide/show
    int _currentStep;
    BOOL _isHidden;
    BOOL _hideIndicators;
    IBOutlet id partnerView; // gets resized when hide/show
    BOOL _awakenedFromNib;
    int _tabBarWidth;

    // drag and drop
    NSEvent *_lastMouseDownEvent; // keep this for dragging reference
    NSEvent *_lastMiddleMouseDownEvent;
    BOOL _didDrag;
    BOOL _closeClicked;

    // iTerm2 additions
    int _modifier;
    BOOL _hasCloseButton;
}

#pragma mark -
#pragma mark Characteristics

+ (NSBundle *)bundle {
    static NSBundle *bundle = nil;
    if (!bundle) bundle = [NSBundle bundleForClass:[PSMTabBarControl class]];
    return bundle;
}

- (float)availableCellWidth {
    float width = [self frame].size.width;
    width = width - [_style leftMarginForTabBarControl] - [_style rightMarginForTabBarControl] - _resizeAreaCompensation;
    return width;
}

- (NSRect)genericCellRect {
    NSRect aRect = [self frame];
    aRect.origin.x = [_style leftMarginForTabBarControl];
    aRect.origin.y = 0.0;
    aRect.size.width = [self availableCellWidth];
    aRect.size.height = kPSMTabBarControlHeight;
    return aRect;
}

#pragma mark -
#pragma mark Constructor/destructor

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization
        _cells = [[NSMutableArray alloc] initWithCapacity:10];
        _animationTimer = nil;

        // default config
        _currentStep = kPSMIsNotBeingResized;
        _orientation = PSMTabBarHorizontalOrientation;
        _useOverflowMenu = YES;
        _allowsBackgroundTabClosing = YES;
        _allowsResizing = YES;
        _cellMinWidth = 100;
        _cellMaxWidth = 280;
        _cellOptimumWidth = 130;
        _hasCloseButton = YES;
        _tabLocation = PSMTab_TopTab;
        _style = [[PSMYosemiteTabStyle alloc] init];

        // the overflow button/menu
        NSRect overflowButtonRect = NSMakeRect([self frame].size.width - [_style rightMarginForTabBarControl] + 1, 0, [_style rightMarginForTabBarControl] - 1, [self frame].size.height);
        _overflowPopUpButton = [[PSMOverflowPopUpButton alloc] initWithFrame:overflowButtonRect pullsDown:YES];
        if (_overflowPopUpButton){
            // configure
            [_overflowPopUpButton setAutoresizingMask:NSViewNotSizable|NSViewMinXMargin];
            [[_overflowPopUpButton cell] accessibilitySetOverrideValue:NSLocalizedStringFromTableInBundle(@"More tabs", @"iTerm", [NSBundle bundleForClass:[self class]], @"VoiceOver label for the button displaying menu of additional overflown tabs on click") forAttribute:NSAccessibilityDescriptionAttribute];
        }

        // new tab button
        NSRect addTabButtonRect = NSMakeRect([self frame].size.width - [_style rightMarginForTabBarControl] + 1, 3.0, 16.0, 16.0);
        _addTabButton = [[PSMRolloverButton alloc] initWithFrame:addTabButtonRect];
        if (_addTabButton){
            NSImage *newButtonImage = [_style addTabButtonImage];
            if (newButtonImage)
                [_addTabButton setUsualImage:newButtonImage];
            newButtonImage = [_style addTabButtonPressedImage];
            if (newButtonImage)
                [_addTabButton setAlternateImage:newButtonImage];
            newButtonImage = [_style addTabButtonRolloverImage];
            if (newButtonImage)
                [_addTabButton setRolloverImage:newButtonImage];
            [_addTabButton setTitle:@""];
            [_addTabButton setImagePosition:NSImageOnly];
            [_addTabButton setButtonType:NSMomentaryChangeButton];
            [_addTabButton setBordered:NO];
            [_addTabButton setBezelStyle:NSShadowlessSquareBezelStyle];
            if (_showAddTabButton){
                [_addTabButton setHidden:NO];
            } else {
                [_addTabButton setHidden:YES];
            }
            [_addTabButton setNeedsDisplay:YES];
        }

        [self registerForDraggedTypes:[NSArray arrayWithObjects:@"com.iterm2.psm.controlitem", nil]];

        // resize
        [self setPostsFrameChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(frameDidChange:) name:NSViewFrameDidChangeNotification object:self];

        // window status
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowStatusDidChange:) name:NSWindowDidBecomeKeyNotification object:[self window]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowStatusDidChange:) name:NSWindowDidResignKeyNotification object:[self window]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidMove:) name:NSWindowDidMoveNotification object:[self window]];

        // modifier for changing tabs changed (iTerm2 addon)
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(modifierChanged:)
                                                     name:kPSMModifierChangedNotification
                                                   object:nil];
    }
    [self setTarget:self];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // Remove bindings.
    NSArray *temp = [[_cells copy] autorelease];
    for (PSMTabBarCell *cell in temp) {
        [cell retain];
        [self removeTabForCell:cell];
        cell.controlView = nil;
        [cell release];
    }

    [_overflowPopUpButton release];
    [_cells release];
    [_tabView release];
    [_addTabButton release];
    [partnerView release];
    [_lastMouseDownEvent release];
    [_lastMiddleMouseDownEvent release];
    [_style release];

    [self unregisterDraggedTypes];

    [super dealloc];
}

- (void)awakeFromNib
{
    // build cells from existing tab view items
    NSArray *existingItems = [_tabView tabViewItems];
    for (NSTabViewItem *item in existingItems) {
        if (![[self representedTabViewItems] containsObject:item]) {
            [self addTabViewItem:item];
        }
    }
}


#pragma mark -
#pragma mark Accessors

- (NSMutableArray *)cells
{
    return _cells;
}

- (NSEvent *)lastMouseDownEvent
{
    return _lastMouseDownEvent;
}

- (void)setLastMouseDownEvent:(NSEvent *)event
{
    [event retain];
    [_lastMouseDownEvent release];
    _lastMouseDownEvent = event;
}

- (NSEvent *)lastMiddleMouseDownEvent
{
    return _lastMiddleMouseDownEvent;
}

- (void)setLastMiddleMouseDownEvent:(NSEvent *)event
{
    [event retain];
    [_lastMiddleMouseDownEvent release];
    _lastMiddleMouseDownEvent = event;
}

- (void)setDelegate:(id<PSMTabBarControlDelegate>)object {
    _delegate = object;

    NSMutableArray *types = [NSMutableArray arrayWithObject:@"com.iterm2.psm.controlitem"];

    //Update the allowed drag types
    if ([[self delegate] respondsToSelector:@selector(allowedDraggedTypesForTabView:)]) {
        [types addObjectsFromArray:[[self delegate] allowedDraggedTypesForTabView:_tabView]];
    }
    [self unregisterDraggedTypes];
    [self registerForDraggedTypes:types];
}

- (NSString *)styleName {
    return [_style name];
}

- (void)setStyle:(id <PSMTabStyle>)newStyle {
    [_style autorelease];
    _style = [newStyle retain];

    // restyle add tab button
    if (_addTabButton){
        NSImage *newButtonImage = [_style addTabButtonImage];
        if (newButtonImage) {
            [_addTabButton setUsualImage:newButtonImage];
        }
        newButtonImage = [_style addTabButtonPressedImage];
        if (newButtonImage) {
            [_addTabButton setAlternateImage:newButtonImage];
        }
        newButtonImage = [_style addTabButtonRolloverImage];
        if (newButtonImage) {
            [_addTabButton setRolloverImage:newButtonImage];
        }
    }

    [self update:_automaticallyAnimates];
}

- (void)setOrientation:(PSMTabBarOrientation)value {
    PSMTabBarOrientation lastOrientation = _orientation;
    _orientation = value;

    if (_tabBarWidth < 10) {
        _tabBarWidth = 120;
    }

    if (lastOrientation != _orientation) {
        [self update];
    }
}

- (void)setDisableTabClose:(BOOL)value {
    _disableTabClose = value;
    [self update:_automaticallyAnimates];
}

- (void)setHideForSingleTab:(BOOL)value {
    _hideForSingleTab = value;
    [self update];
}

- (void)setShowAddTabButton:(BOOL)value {
    _showAddTabButton = value;
    [self update];
}

- (void)setCellMinWidth:(int)value {
    _cellMinWidth = value;
    [self update:_automaticallyAnimates];
}

- (void)setCellMaxWidth:(int)value {
    _cellMaxWidth = value;
    [self update:_automaticallyAnimates];
}

- (void)setCellOptimumWidth:(int)value {
    _cellOptimumWidth = value;
    [self update:_automaticallyAnimates];
}

- (void)setSizeCellsToFit:(BOOL)value {
    _sizeCellsToFit = value;
    [self update:_automaticallyAnimates];
}

- (void)setUseOverflowMenu:(BOOL)value {
    _useOverflowMenu = value;
    [self update];
}

- (PSMRolloverButton *)addTabButton {
    return _addTabButton;
}

- (void)setTabLocation:(int)value {
    _tabLocation = value;
    switch (value) {
        case PSMTab_TopTab:
        case PSMTab_BottomTab:
            [self setOrientation:PSMTabBarHorizontalOrientation];
            break;

        case PSMTab_LeftTab:
            [self setOrientation:PSMTabBarVerticalOrientation];
            break;
    }
}

- (void)setAllowsBackgroundTabClosing:(BOOL)value {
    _allowsBackgroundTabClosing = value;
    [self update];
}

#pragma mark -
#pragma mark Functionality

- (NSLineBreakMode)truncationStyle {
    if (_cells.count <= 1 || !self.smartTruncation) {
        return NSLineBreakByTruncatingTail;
    }
    NSCountedSet *prefixCounts = [[[NSCountedSet alloc] init] autorelease];
    NSCountedSet *suffixCounts = [[[NSCountedSet alloc] init] autorelease];
    NSMutableSet *uniqueTitles = [NSMutableSet set];
    static NSInteger const kPrefixOrSuffixLength = 5;
    for (PSMTabBarCell *cell in _cells) {
        NSString *title = [cell title];
        if (title.length < kPrefixOrSuffixLength) {
            continue;
        }
        [uniqueTitles addObject:title];
        NSString *prefix = [title substringToIndex:kPrefixOrSuffixLength];
        NSString *suffix = [title substringFromIndex:(NSInteger)title.length - kPrefixOrSuffixLength];
        
        [prefixCounts addObject:prefix];
        [suffixCounts addObject:suffix];
    }
    if (uniqueTitles.count == 0) {
        return NSLineBreakByTruncatingTail;
    }

    if (prefixCounts.count >= suffixCounts.count) {
        return NSLineBreakByTruncatingTail;
    } else {
        return NSLineBreakByTruncatingHead;
    }
}

- (void)addTabViewItem:(NSTabViewItem *)item atIndex:(NSUInteger)i {
    // create cell
    PSMTabBarCell *cell = [[PSMTabBarCell alloc] initWithControlView:self];
    cell.truncationStyle = [self truncationStyle];
    [cell setRepresentedObject:item];
    [cell setModifierString:[self _modifierString]];

    // add to collection
    [_cells insertObject:cell atIndex:i];

    // bind it up
    [self initializeStateForCell:cell];
    [self bindPropertiesForCell:cell andTabViewItem:item];
    [cell release];
}

- (void)addTabViewItem:(NSTabViewItem *)item {
    [self addTabViewItem:item atIndex:[_cells count]];
}

- (void)removeTabForCell:(PSMTabBarCell *)cell {
    // unbind
    [cell unbind:@"title"];

    // remove indicator
    if ([[self subviews] containsObject:[cell indicator]]) {
        [[cell indicator] setDelegate:nil];
        [[cell indicator] removeFromSuperview];
    }
    // remove tracking
    [[NSNotificationCenter defaultCenter] removeObserver:cell];

    if ([cell closeButtonTrackingTag] != 0) {
        [self removeTrackingRect:[cell closeButtonTrackingTag]];
        [cell setCloseButtonTrackingTag:0];
    }
    if ([cell cellTrackingTag] != 0) {
        [self removeTrackingRect:[cell cellTrackingTag]];
        [cell setCellTrackingTag:0];
    }
    [self removeAllToolTips];

    // pull from collection
    [_cells removeObject:cell];
}

#pragma mark -
#pragma mark Hide/Show

- (void)hideTabBar:(BOOL)hide animate:(BOOL)animate {
    if (!_awakenedFromNib || (_isHidden && hide) || (!_isHidden && !hide) || (_currentStep != kPSMIsNotBeingResized)) {
        return;
    }

    [[self subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
    _hideIndicators = YES;

    _isHidden = hide;
    _currentStep = 0;
    if (!animate)
        _currentStep = (int)kPSMHideAnimationSteps;

    float partnerOriginalSize, partnerOriginalOrigin, myOriginalSize, myOriginalOrigin, partnerTargetSize, partnerTargetOrigin, myTargetSize, myTargetOrigin;

    // target values for partner
    if ([self orientation] == PSMTabBarHorizontalOrientation) {
        // current (original) values
        myOriginalSize = [self frame].size.height;
        myOriginalOrigin = [self frame].origin.y;
        if (partnerView) {
            partnerOriginalSize = [partnerView frame].size.height;
            partnerOriginalOrigin = [partnerView frame].origin.y;
        } else {
            partnerOriginalSize = [[self window] frame].size.height;
            partnerOriginalOrigin = [[self window] frame].origin.y;
        }

        if (partnerView) {
            // above or below me?
            if ((myOriginalOrigin - 22) > partnerOriginalOrigin) {
                // partner is below me
                if (_isHidden) {
                    // I'm shrinking
                    myTargetOrigin = myOriginalOrigin + 21;
                    myTargetSize = myOriginalSize - 21;
                    partnerTargetOrigin = partnerOriginalOrigin;
                    partnerTargetSize = partnerOriginalSize + 21;
                } else {
                    // I'm growing
                    myTargetOrigin = myOriginalOrigin - 21;
                    myTargetSize = myOriginalSize + 21;
                    partnerTargetOrigin = partnerOriginalOrigin;
                    partnerTargetSize = partnerOriginalSize - 21;
                }
            } else {
                // partner is above me
                if (_isHidden) {
                    // I'm shrinking
                    myTargetOrigin = myOriginalOrigin;
                    myTargetSize = myOriginalSize - 21;
                    partnerTargetOrigin = partnerOriginalOrigin - 21;
                    partnerTargetSize = partnerOriginalSize + 21;
                } else {
                    // I'm growing
                    myTargetOrigin = myOriginalOrigin;
                    myTargetSize = myOriginalSize + 21;
                    partnerTargetOrigin = partnerOriginalOrigin + 21;
                    partnerTargetSize = partnerOriginalSize - 21;
                }
            }
        } else {
            // for window movement
            if (_isHidden) {
                // I'm shrinking
                myTargetOrigin = myOriginalOrigin;
                myTargetSize = myOriginalSize - 21;
                partnerTargetOrigin = partnerOriginalOrigin + 21;
                partnerTargetSize = partnerOriginalSize - 21;
            } else {
                // I'm growing
                myTargetOrigin = myOriginalOrigin;
                myTargetSize = myOriginalSize + 21;
                partnerTargetOrigin = partnerOriginalOrigin - 21;
                partnerTargetSize = partnerOriginalSize + 21;
            }
        }
    } else {
        // current (original) values
        myOriginalSize = [self frame].size.width;
        myOriginalOrigin = [self frame].origin.x;
        if (partnerView) {
            partnerOriginalSize = [partnerView frame].size.width;
            partnerOriginalOrigin = [partnerView frame].origin.x;
        } else {
            partnerOriginalSize = [[self window] frame].size.width;
            partnerOriginalOrigin = [[self window] frame].origin.x;
        }

        if (partnerView) {
            //to the left or right?
            if (myOriginalOrigin < partnerOriginalOrigin + partnerOriginalSize) {
                // partner is to the left
                if (_isHidden) {
                    // I'm shrinking
                    myTargetOrigin = myOriginalOrigin;
                    myTargetSize = 1;
                    partnerTargetOrigin = partnerOriginalOrigin - myOriginalSize + 1;
                    partnerTargetSize = partnerOriginalSize + myOriginalSize - 1;
                    _tabBarWidth = myOriginalSize;
                } else {
                    // I'm growing
                    myTargetOrigin = myOriginalOrigin;
                    myTargetSize = myOriginalSize + _tabBarWidth;
                    partnerTargetOrigin = partnerOriginalOrigin + _tabBarWidth;
                    partnerTargetSize = partnerOriginalSize - _tabBarWidth;
                }
            } else {
                // partner is to the right
                if (_isHidden) {
                    // I'm shrinking
                    myTargetOrigin = myOriginalOrigin + myOriginalSize;
                    myTargetSize = 1;
                    partnerTargetOrigin = partnerOriginalOrigin;
                    partnerTargetSize = partnerOriginalSize + myOriginalSize;
                    _tabBarWidth = myOriginalSize;
                } else {
                    // I'm growing
                    myTargetOrigin = myOriginalOrigin - _tabBarWidth;
                    myTargetSize = myOriginalSize + _tabBarWidth;
                    partnerTargetOrigin = partnerOriginalOrigin;
                    partnerTargetSize = partnerOriginalSize - _tabBarWidth;
                }
            }
        } else {
            // for window movement
            if (_isHidden) {
                // I'm shrinking
                myTargetOrigin = myOriginalOrigin;
                myTargetSize = 1;
                partnerTargetOrigin = partnerOriginalOrigin + myOriginalSize - 1;
                partnerTargetSize = partnerOriginalSize - myOriginalSize + 1;
                _tabBarWidth = myOriginalSize;
            } else {
                // I'm growing
                myTargetOrigin = myOriginalOrigin;
                myTargetSize = _tabBarWidth;
                partnerTargetOrigin = partnerOriginalOrigin - _tabBarWidth + 1;
                partnerTargetSize = partnerOriginalSize + _tabBarWidth - 1;
            }
        }
    }

    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:myOriginalOrigin], @"myOriginalOrigin", [NSNumber numberWithFloat:partnerOriginalOrigin], @"partnerOriginalOrigin", [NSNumber numberWithFloat:myOriginalSize], @"myOriginalSize", [NSNumber numberWithFloat:partnerOriginalSize], @"partnerOriginalSize", [NSNumber numberWithFloat:myTargetOrigin], @"myTargetOrigin", [NSNumber numberWithFloat:partnerTargetOrigin], @"partnerTargetOrigin", [NSNumber numberWithFloat:myTargetSize], @"myTargetSize", [NSNumber numberWithFloat:partnerTargetSize], @"partnerTargetSize", nil];
    [NSTimer scheduledTimerWithTimeInterval:(1.0/20.0) target:self selector:@selector(animateShowHide:) userInfo:userInfo repeats:YES];
}

- (void)animateShowHide:(NSTimer *)timer
{
    // moves the frame of the tab bar and window (or partner view) linearly to hide or show the tab bar
    NSRect myFrame = [self frame];
    NSDictionary *userInfo = [timer userInfo];
    float myCurrentOrigin = ([[userInfo objectForKey:@"myOriginalOrigin"] floatValue] + (([[userInfo objectForKey:@"myTargetOrigin"] floatValue] - [[userInfo objectForKey:@"myOriginalOrigin"] floatValue]) * (_currentStep/kPSMHideAnimationSteps)));
    float myCurrentSize = ([[userInfo objectForKey:@"myOriginalSize"] floatValue] + (([[userInfo objectForKey:@"myTargetSize"] floatValue] - [[userInfo objectForKey:@"myOriginalSize"] floatValue]) * (_currentStep/kPSMHideAnimationSteps)));
    float partnerCurrentOrigin = ([[userInfo objectForKey:@"partnerOriginalOrigin"] floatValue] + (([[userInfo objectForKey:@"partnerTargetOrigin"] floatValue] - [[userInfo objectForKey:@"partnerOriginalOrigin"] floatValue]) * (_currentStep/kPSMHideAnimationSteps)));
    float partnerCurrentSize = ([[userInfo objectForKey:@"partnerOriginalSize"] floatValue] + (([[userInfo objectForKey:@"partnerTargetSize"] floatValue] - [[userInfo objectForKey:@"partnerOriginalSize"] floatValue]) * (_currentStep/kPSMHideAnimationSteps)));

    NSRect myNewFrame;
    if ([self orientation] == PSMTabBarHorizontalOrientation) {
        myNewFrame = NSMakeRect(myFrame.origin.x, myCurrentOrigin, myFrame.size.width, myCurrentSize);
    } else {
        myNewFrame = NSMakeRect(myCurrentOrigin, myFrame.origin.y, myCurrentSize, myFrame.size.height);
    }

    if (partnerView) {
        // resize self and view
        NSRect resizeRect;
        if ([self orientation] == PSMTabBarHorizontalOrientation) {
            resizeRect = NSMakeRect([partnerView frame].origin.x, partnerCurrentOrigin, [partnerView frame].size.width, partnerCurrentSize);
        } else {
            resizeRect = NSMakeRect(partnerCurrentOrigin, [partnerView frame].origin.y, partnerCurrentSize, [partnerView frame].size.height);
        }
        [partnerView setFrame:resizeRect];
        [partnerView setNeedsDisplay:YES];
        [self setFrame:myNewFrame];
    } else {
        // resize self and window
        NSRect resizeRect;
        if ([self orientation] == PSMTabBarHorizontalOrientation) {
            resizeRect = NSMakeRect([[self window] frame].origin.x, partnerCurrentOrigin, [[self window] frame].size.width, partnerCurrentSize);
        } else {
            resizeRect = NSMakeRect(partnerCurrentOrigin, [[self window] frame].origin.y, partnerCurrentSize, [[self window] frame].size.height);
        }
        [[self window] setFrame:resizeRect display:YES];
        [self setFrame:myNewFrame];
    }

    // next
    _currentStep++;
    if (_currentStep == kPSMHideAnimationSteps + 1) {
        _currentStep = kPSMIsNotBeingResized;
        [self viewDidEndLiveResize];
        _hideIndicators = NO;
        [self update];

        // send the delegate messages
        if (_isHidden) {
            if ([[self delegate] respondsToSelector:@selector(tabView:tabBarDidHide:)]) {
                [[self delegate] tabView:[self tabView] tabBarDidHide:self];
            }
        } else {
            if ([[self delegate] respondsToSelector:@selector(tabView:tabBarDidUnhide:)]) {
                [[self delegate] tabView:[self tabView] tabBarDidUnhide:self];
            }
        }

        [timer invalidate];
    }
    [[self window] display];
}

- (BOOL)isTabBarHidden
{
    return _isHidden;
}

- (id)partnerView
{
    return partnerView;
}

- (void)setPartnerView:(id)view
{
    [partnerView release];
    [view retain];
    partnerView = view;
}

#pragma mark -
#pragma mark Drawing

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)rect
{
    for (PSMTabBarCell *cell in [self cells]) {
        [cell setIsLast:NO];
    }
    [[[self cells] lastObject] setIsLast:YES];
    [_style drawTabBar:self inRect:rect horizontal:(_orientation == PSMTabBarHorizontalOrientation)];
}

- (void)moveTabAtIndex:(NSInteger)sourceIndex toIndex:(NSInteger)destIndex
{
    NSTabViewItem *theItem = [_tabView tabViewItemAtIndex:sourceIndex];
    BOOL reselect = ([_tabView selectedTabViewItem] == theItem);

    id<NSTabViewDelegate> tempDelegate = [_tabView delegate];
    [_tabView setDelegate:nil];
    [theItem retain];
    [_tabView removeTabViewItem:theItem];
    [_tabView insertTabViewItem:theItem atIndex:destIndex];
    [theItem release];

    id cell = [_cells objectAtIndex:sourceIndex];
    [cell retain];
    [_cells removeObjectAtIndex:sourceIndex];
    [_cells insertObject:cell atIndex:destIndex];
    [cell release];

    [_tabView setDelegate:tempDelegate];

    if (reselect) {
        [_tabView selectTabViewItem:theItem];
    }

    [self update:YES];
}

- (void)update
{
    [self update:NO];
}

- (void)update:(BOOL)animate
{
    // abandon hope, all ye who enter here :-)
    // this method handles all of the cell layout, and is called when something changes to require the refresh.  This method is not called during drag and drop; see the PSMTabDragAssistant's calculateDragAnimationForTabBar: method, which does layout in that case.

    // make sure all of our tabs are accounted for before updating
    if ([_tabView numberOfTabViewItems] != [_cells count]) {
        return;
    }

    // hide/show? (these return if already in desired state)
    if ((_hideForSingleTab) && ([_cells count] <= 1)) {
        [self hideTabBar:YES animate:YES];
    } else {
        [self hideTabBar:NO animate:YES];
    }

    [self _removeCellTrackingRects];

    // calculate number of cells to fit in control and cell widths
    int i, cellCount = [_cells count];
    float availableWidth = [self availableCellWidth], currentOrigin = 0;
    NSMutableArray *newWidths = [NSMutableArray arrayWithCapacity:cellCount];
    int numberOfVisibleCells = ([self orientation] == PSMTabBarHorizontalOrientation) ? 1 : 0;
    float totalOccupiedWidth = 0.0;
    NSRect cellRect = [self genericCellRect];

    if ([self orientation] == PSMTabBarVerticalOrientation) {
        currentOrigin = [[self style] topMarginForTabBarControl];
    }

    NSLineBreakMode truncationStyle = [self truncationStyle];
    
    for (i = 0; i < cellCount; i++) {
        PSMTabBarCell *cell = [_cells objectAtIndex:i];
        cell.truncationStyle = truncationStyle;
        cell.hasCloseButton = _hasCloseButton;
        [cell updateForStyle];
        float width;

        // suppress close button?
        cell.isCloseButtonSuppressed = [self disableTabClose];

        if ([self orientation] == PSMTabBarHorizontalOrientation) {
            // Determine cell width
            if (_sizeCellsToFit) {
                width = MAX(_cellMinWidth, [cell desiredWidthOfCell]);
                if (width > _cellMaxWidth) {
                    width = _cellMaxWidth;
                }
            } else {
                width = _cellOptimumWidth;
            }

            //check to see if there is not enough space to place all tabs as preferred
            totalOccupiedWidth += width;
            if (totalOccupiedWidth >= availableWidth) {
                //if we're not going to use the overflow menu, cram all the tab cells into the bar
                if (!_useOverflowMenu) {
                    int j, averageWidth = (availableWidth / cellCount);

                    [newWidths removeAllObjects];

                    for (j = 0; j < cellCount; j++) {
                        float desiredWidth = [[_cells objectAtIndex:j] desiredWidthOfCell];
                        [newWidths addObject:[NSNumber numberWithFloat:(desiredWidth < averageWidth && [self sizeCellsToFit]) ? desiredWidth : averageWidth]];
                    }
                    break;
                }

                numberOfVisibleCells = i;
                if (_sizeCellsToFit) {
                    int neededWidth = width - (totalOccupiedWidth - availableWidth); //the amount of space needed to fit the next cell in
                    // can I squeeze it in without violating min cell width?
                    int widthIfAllMin = (numberOfVisibleCells + 1) * _cellMinWidth;

                    if ((width + widthIfAllMin) <= availableWidth) {
                        // squeeze - distribute needed sacrifice among all cells
                        int q;
                        for (q = (i - 1); q >= 0; q--) {
                            int desiredReduction = (int)neededWidth / (q + 1);
                            if (([[newWidths objectAtIndex:q] floatValue] - desiredReduction) < _cellMinWidth) {
                                int actualReduction = (int)[[newWidths objectAtIndex:q] floatValue] - _cellMinWidth;
                                [newWidths replaceObjectAtIndex:q withObject:[NSNumber numberWithFloat:_cellMinWidth]];
                                neededWidth -= actualReduction;
                            } else {
                                int newCellWidth = (int)[[newWidths objectAtIndex:q] floatValue] - desiredReduction;
                                [newWidths replaceObjectAtIndex:q withObject:[NSNumber numberWithFloat:newCellWidth]];
                                neededWidth -= desiredReduction;
                            }
                        }

                        int totalWidth = [[newWidths valueForKeyPath:@"@sum.intValue"] intValue];
                        int thisWidth = width - neededWidth; //width the last cell would want

                        //append a final cell if there is enough room, otherwise stretch all the cells out to fully fit the bar
                        if (availableWidth - totalWidth > thisWidth) {
                            [newWidths addObject:[NSNumber numberWithFloat:thisWidth]];
                            numberOfVisibleCells++;
                            totalWidth += thisWidth;
                        }

                        if (totalWidth < availableWidth) {
                            int leftoverWidth = availableWidth - totalWidth;
                            int q2;

                            for (q2 = i - 1; q2 >= 0; q2--) {
                                int desiredAddition = (int)leftoverWidth / (q2 + 1);
                                int newCellWidth = (int)[[newWidths objectAtIndex:q2] floatValue] + desiredAddition;
                                [newWidths replaceObjectAtIndex:q2 withObject:[NSNumber numberWithFloat:newCellWidth]];
                                leftoverWidth -= desiredAddition;
                            }
                        }
                    } else {
                        // stretch - distribute leftover room among cells
                        int leftoverWidth = availableWidth - totalOccupiedWidth + width;
                        int q;

                        for (q = i - 1; q >= 0; q--) {
                            int desiredAddition = (int)leftoverWidth / (q + 1);
                            int newCellWidth = (int)[[newWidths objectAtIndex:q] floatValue] + desiredAddition;
                            [newWidths replaceObjectAtIndex:q withObject:[NSNumber numberWithFloat:newCellWidth]];
                            leftoverWidth -= desiredAddition;
                        }
                    }

                    //make sure there are at least two items in the tab bar
                    if (numberOfVisibleCells < 2 && [_cells count] > 1) {
                        PSMTabBarCell *cell1 = [_cells objectAtIndex:0], *cell2 = [_cells objectAtIndex:1];
                        NSNumber *cellWidth;

                        [newWidths removeAllObjects];
                        totalOccupiedWidth = 0;

                        cellWidth = [NSNumber numberWithFloat:[cell1 desiredWidthOfCell] < availableWidth * 0.5f ? [cell1 desiredWidthOfCell] : availableWidth * 0.5f];
                        [newWidths addObject:cellWidth];
                        totalOccupiedWidth += [cellWidth floatValue];

                        cellWidth = [NSNumber numberWithFloat:[cell2 desiredWidthOfCell] < (availableWidth - totalOccupiedWidth) ? [cell2 desiredWidthOfCell] : (availableWidth - totalOccupiedWidth)];
                        [newWidths addObject:cellWidth];
                        totalOccupiedWidth += [cellWidth floatValue];

                        if (totalOccupiedWidth < availableWidth) {
                            [newWidths replaceObjectAtIndex:0 withObject:[NSNumber numberWithFloat:availableWidth - [cellWidth floatValue]]];
                        }
                    }

                    break; // done assigning widths; remaining cells go in overflow menu
                } else {
                    int revisedWidth = availableWidth / (i + 1);
                    if (revisedWidth >= _cellMinWidth) {
                        int q;
                        totalOccupiedWidth = 0;
                        for (q = 0; q < [newWidths count]; q++) {
                            [newWidths replaceObjectAtIndex:q withObject:[NSNumber numberWithFloat:revisedWidth]];
                            totalOccupiedWidth += revisedWidth;
                        }
                        // just squeezed this one in...
                        [newWidths addObject:[NSNumber numberWithFloat:revisedWidth]];
                        totalOccupiedWidth += revisedWidth;
                        numberOfVisibleCells++;
                    } else {
                        // couldn't fit that last one...
                        break;
                    }
                }
            } else {
                numberOfVisibleCells = cellCount;
                [newWidths addObject:[NSNumber numberWithFloat:width]];
            }
        } else {
            //lay out vertical tabs
            if (currentOrigin + cellRect.size.height <= [self frame].size.height) {
                [newWidths addObject:[NSNumber numberWithFloat:currentOrigin]];
                numberOfVisibleCells++;
                currentOrigin += cellRect.size.height;
            } else {
                //out of room, the remaining tabs go into overflow
                if ([newWidths count] > 0 && [self frame].size.height - currentOrigin < 17) {
                    [newWidths removeLastObject];
                    numberOfVisibleCells--;
                }
                break;
            }
        }
    }

    for (PSMTabBarCell *cell in _cells) {
        // Remove highlight if cursor is no longer in cell. Could happen if
        // cell moves because of added/removed tab. Tracking rects aren't smart
        // enough to handle this.
        [cell updateHighlight];
    }

    if ((animate || _animationTimer != nil) && [self orientation] == PSMTabBarHorizontalOrientation && [_cells count] > 0) {
        //animate only on horizontal tab bars
        if (_animationTimer) {
            [_animationTimer invalidate];
        }

        _animationDelta = 0.0f;
        _animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(_animateCells:) userInfo:newWidths repeats:YES];
    } else {
        [self _finishCellUpdate:newWidths];
        [self setNeedsDisplay];
    }

}

- (void)_removeCellTrackingRects
{
    // size all cells appropriately and create tracking rects
    // nuke old tracking rects
    int i, cellCount = [_cells count];
    for (i = 0; i < cellCount; i++) {
        id cell = [_cells objectAtIndex:i];
        [[NSNotificationCenter defaultCenter] removeObserver:cell];
        if ([cell closeButtonTrackingTag] != 0) {
            [self removeTrackingRect:[cell closeButtonTrackingTag]];
            [cell setCloseButtonTrackingTag:0];
        }

        if ([cell cellTrackingTag] != 0) {
            [self removeTrackingRect:[cell cellTrackingTag]];
            [cell setCellTrackingTag:0];
        }
    }

    //remove all tooltip rects
    [self removeAllToolTips];
}

- (void)_animateCells:(NSTimer *)timer
{
    NSArray *targetWidths = [timer userInfo];
    int i, numberOfVisibleCells = [targetWidths count];
    float totalChange = 0.0f;
    BOOL updated = NO;

    if ([_cells count] > 0) {
        //compare our target widths with the current widths and move towards the target
        for (i = 0; i < [_cells count]; i++) {
            PSMTabBarCell *currentCell = [_cells objectAtIndex:i];
            NSRect cellFrame = [currentCell frame];
            cellFrame.origin.x += totalChange;

            if (i < numberOfVisibleCells) {
                float target = [[targetWidths objectAtIndex:i] floatValue];

                if (fabs(cellFrame.size.width - target) < _animationDelta) {
                    cellFrame.size.width = target;
                    totalChange += cellFrame.size.width - target;
                    [currentCell setFrame:cellFrame];
                } else if (cellFrame.size.width > target) {
                    cellFrame.size.width -= _animationDelta;
                    totalChange -= _animationDelta;
                    updated = YES;
                } else if (cellFrame.size.width < target) {
                    cellFrame.size.width += _animationDelta;
                    totalChange += _animationDelta;
                    [currentCell setFrame:cellFrame];
                    updated = YES;
                }
            }

            [currentCell setFrame:cellFrame];
        }

        _animationDelta += 3.0f;
    }

    if (!updated) {
        [self _finishCellUpdate:targetWidths];
        [timer invalidate];
        _animationTimer = nil;
    }

    [self setNeedsDisplay];
}

- (void)_finishCellUpdate:(NSArray *)newWidths
{
    //setup overflow menu
    NSMenu *overflowMenu = [self _setupCells:newWidths];

    if (overflowMenu) {
        [self _setupOverflowMenu:overflowMenu];
    }

    [_overflowPopUpButton setHidden:(overflowMenu == nil)];

    //setup add tab button
    if (!overflowMenu && _showAddTabButton) {
        NSRect cellRect = [self genericCellRect];
        cellRect.size = [_addTabButton frame].size;

        if ([self orientation] == PSMTabBarHorizontalOrientation) {
            cellRect.origin.y = kSPMTabBarCellInternalYMargin;
            cellRect.origin.x += [[newWidths valueForKeyPath:@"@sum.floatValue"] floatValue] + 2;
        } else {
            cellRect.origin.x = 0;
            cellRect.origin.y = [[newWidths lastObject] floatValue];
        }

        [self _setupAddTabButton:cellRect];
    } else {
        [_addTabButton setHidden:YES];
    }
}

- (NSMenu *)_setupCells:(NSArray *)newWidths {
    NSRect cellRect = [self genericCellRect];
    int i, cellCount = [_cells count], numberOfVisibleCells = [newWidths count];
    NSMenu *overflowMenu = nil;

    // Set up cells with frames and rects
    for (i = 0; i < cellCount; i++) {
        PSMTabBarCell *cell = [_cells objectAtIndex:i];
        int tabState = 0;
        if (i < numberOfVisibleCells) {
            // set cell frame
            if ([self orientation] == PSMTabBarHorizontalOrientation) {
                cellRect.size.width = [[newWidths objectAtIndex:i] floatValue];
            } else {
                cellRect.size.width = [self frame].size.width;
                cellRect.origin.y = [[newWidths objectAtIndex:i] floatValue];
                cellRect.origin.x = 0;
            }
            [cell setFrame:cellRect];

            NSTrackingRectTag tag;

            // close button tracking rect
            if ([cell hasCloseButton] &&
                ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]] ||
                 [self allowsBackgroundTabClosing])) {
                    NSPoint mousePoint =
                    [self convertPoint:[[self window] pointFromScreenCoords:[NSEvent mouseLocation]]
                              fromView:nil];
                    NSRect closeRect = [cell closeButtonRectForFrame:cellRect];

                    // Add the tracking rect for the close button highlight.
                    if ([cell closeButtonTrackingTag]) {
                        [self removeTrackingRect:[cell closeButtonTrackingTag]];
                    }
                    tag = [self addTrackingRect:closeRect owner:cell userData:nil assumeInside:NO];
                    [cell setCloseButtonTrackingTag:tag];

                    // highlight the close button if the currently selected tab has the mouse over it
                    // this will happen if the user clicks a close button in a tab and all the tabs are
                    // rearranged
                    if ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]] &&
                        [[NSApp currentEvent] type] != NSLeftMouseDown &&
                        NSMouseInRect(mousePoint, closeRect, [self isFlipped])) {
                        [cell setCloseButtonOver:YES];
                    }
                } else {
                    [cell setCloseButtonOver:NO];
                }

            // Add entire-tab tracking rect.
            if ([cell cellTrackingTag]) {
                [self removeTrackingRect:[cell cellTrackingTag]];
            }
            tag = [self addTrackingRect:cellRect owner:cell userData:nil assumeInside:NO];
            [cell setCellTrackingTag:tag];
            [cell setEnabled:YES];

            //add the tooltip tracking rect
            [self addToolTipRect:cellRect owner:self userData:nil];

            // selected? set tab states...
            if ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]]) {
                [cell setState:NSOnState];
                tabState |= PSMTab_SelectedMask;
                // previous cell
                if (i > 0) {
                    [[_cells objectAtIndex:i-1] setTabState:([(PSMTabBarCell *)[_cells objectAtIndex:i-1] tabState] | PSMTab_RightIsSelectedMask)];
                }
                // next cell - see below
            } else {
                [cell setState:NSOffState];
                // see if prev cell was selected
                if (i > 0) {
                    if ([[_cells objectAtIndex:i-1] state] == NSOnState){
                        tabState |= PSMTab_LeftIsSelectedMask;
                    }
                }
            }
            // more tab states
            if (cellCount == 1) {
                tabState |= PSMTab_PositionLeftMask | PSMTab_PositionRightMask | PSMTab_PositionSingleMask;
            } else if (i == 0) {
                tabState |= PSMTab_PositionLeftMask;
            } else if (i-1 == cellCount) {
                tabState |= PSMTab_PositionRightMask;
            }
            [cell setTabState:tabState];
            [cell setIsInOverflowMenu:NO];

            // indicator
            if (![[cell indicator] isHidden] && !_hideIndicators) {
                [[cell indicator] setFrame:[cell indicatorRectForFrame:cellRect]];
                if (![[self subviews] containsObject:[cell indicator]]) {
                    [self addSubview:[cell indicator]];
                    [[cell indicator] setAnimate:YES];
                }
            }

            // next...
            cellRect.origin.x += [[newWidths objectAtIndex:i] floatValue];

        } else {
            // set up menu items
            NSMenuItem *menuItem;
            if (overflowMenu == nil) {
                overflowMenu = [[[NSMenu alloc] initWithTitle:@"TITLE"] autorelease];
                [overflowMenu insertItemWithTitle:@"FIRST" action:nil keyEquivalent:@"" atIndex:0]; // Because the overflowPupUpButton is a pull down menu
            }
            menuItem = [[NSMenuItem alloc] initWithTitle:[[cell attributedStringValue] string] action:@selector(overflowMenuAction:) keyEquivalent:@""];
            [menuItem setTarget:self];
            [menuItem setRepresentedObject:[cell representedObject]];
            [cell setIsInOverflowMenu:YES];
            [[cell indicator] removeFromSuperview];
            if ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]]) {
                [menuItem setState:NSOnState];
            }

            if ([cell hasIcon]) {
                [menuItem setImage:[(id)[[cell representedObject] identifier] icon]];
            }

            if ([cell count] > 0) {
                [menuItem setTitle:[[menuItem title] stringByAppendingFormat:@" (%d)", [cell count]]];
            }

            [overflowMenu addItem:menuItem];
            [menuItem release];
        }
    }

    return overflowMenu;
}

- (void)_setupOverflowMenu:(NSMenu *)overflowMenu
{
    NSRect cellRect;
    int i;

    cellRect.size.height = kPSMTabBarControlHeight;
    cellRect.size.width = [_style rightMarginForTabBarControl];
    if ([self orientation] == PSMTabBarHorizontalOrientation) {
        cellRect.origin.y = 0;
        cellRect.origin.x = [self frame].size.width - [_style rightMarginForTabBarControl] + (_resizeAreaCompensation ? -_resizeAreaCompensation : 1);
    } else {
        cellRect.origin.x = 0;
        cellRect.origin.y = [self frame].size.height - kPSMTabBarControlHeight;
        cellRect.size.width = [self frame].size.width;
    }

    if (![[self subviews] containsObject:_overflowPopUpButton]) {
        [self addSubview:_overflowPopUpButton];
    }
    [_overflowPopUpButton setFrame:cellRect];

    if (overflowMenu) {
        // Have a candidate for new overflow menu. Does it contain the same information as the current one?
        // If they're equal, we don't want to update the menu since this happens several times per second
        // while the user is visiting the menu. But reading it is fine.
        BOOL equal = YES;
        equal = [_overflowPopUpButton menu] && [[_overflowPopUpButton menu] numberOfItems ] == [overflowMenu numberOfItems];
        for (i = 0; equal && i < [overflowMenu numberOfItems]; i++) {
            NSMenuItem *currentItem = [[_overflowPopUpButton menu] itemAtIndex:i];
            NSMenuItem *newItem = [overflowMenu itemAtIndex:i];
            if (([newItem state] != [currentItem state]) ||
                    ([[newItem title] compare:[currentItem title]] != NSOrderedSame) ||
                    ([newItem image] != [currentItem image])) {
                equal = NO;
            }
        }

        if (!equal) {
            [_overflowPopUpButton setMenu:overflowMenu];
        }
    }
}

- (void)_setupAddTabButton:(NSRect)frame
{
    if (![[self subviews] containsObject:_addTabButton]) {
        [self addSubview:_addTabButton];
    }

    if ([_addTabButton isHidden] && _showAddTabButton) {
        [_addTabButton setHidden:NO];
    }

    [_addTabButton setImage:[_style addTabButtonImage]];
    [_addTabButton setFrame:frame];
    [_addTabButton setNeedsDisplay:YES];
}

#pragma mark -
#pragma mark Mouse Tracking

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return YES;
}

- (void)otherMouseDown:(NSEvent *)theEvent {
    if ([theEvent buttonNumber] == 2) {
        [self setLastMiddleMouseDownEvent:theEvent];
    }
}

- (void)mouseDown:(NSEvent *)theEvent
{
    _didDrag = NO;

    // keep for dragging
    [self setLastMouseDownEvent:theEvent];
    // what cell?
    NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    NSRect frame = [self frame];

    if ([self orientation] == PSMTabBarVerticalOrientation && [self allowsResizing] && partnerView && (mousePt.x > frame.size.width - 3)) {
        _resizing = YES;
    }

    NSRect cellFrame;
    PSMTabBarCell *cell = [self cellForPoint:mousePt cellFrame:&cellFrame];
    if (cell) {
        BOOL overClose = NSMouseInRect(mousePt, [cell closeButtonRectForFrame:cellFrame], [self isFlipped]);
        if (overClose &&
            cell.closeButtonVisible &&
            ([self allowsBackgroundTabClosing] || [[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]])) {
            [cell setCloseButtonOver:NO];
            [cell setCloseButtonPressed:YES];
            _closeClicked = YES;
        } else {
            [cell setCloseButtonPressed:NO];
            if ([theEvent clickCount] == 2) {
                [self performSelector:@selector(tabDoubleClick:) withObject:cell];
            }
            else {
                if (_selectsTabsOnMouseDown) {
                    [self performSelector:@selector(tabClick:) withObject:cell];
                }
            }
        }
        [self setNeedsDisplay];
    }
    else {
        if ([theEvent clickCount] == 2) {
            [self performSelector:@selector(tabBarDoubleClick)];
        }
    }
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    if ([self lastMouseDownEvent] == nil) {
        return;
    }

    NSPoint currentPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];

    if (_resizing) {
        NSRect frame = [self frame];
        float resizeAmount = [theEvent deltaX];
        if ((currentPoint.x > frame.size.width && resizeAmount > 0) || (currentPoint.x < frame.size.width && resizeAmount < 0)) {
            [[NSCursor resizeLeftRightCursor] push];

            NSRect partnerFrame = [partnerView frame];

            //do some bounds checking
            if ((frame.size.width + resizeAmount > [self cellMinWidth]) && (frame.size.width + resizeAmount < [self cellMaxWidth])) {
                frame.size.width += resizeAmount;
                partnerFrame.size.width -= resizeAmount;
                partnerFrame.origin.x += resizeAmount;

                [self setFrame:frame];
                [partnerView setFrame:partnerFrame];
                [[self superview] setNeedsDisplay:YES];
            }
        }
        return;
    }

    NSRect cellFrame;
    NSPoint trackingStartPoint = [self convertPoint:[[self lastMouseDownEvent] locationInWindow] fromView:nil];
    PSMTabBarCell *cell = [self cellForPoint:trackingStartPoint cellFrame:&cellFrame];
    if (cell) {
        //check to see if the close button was the target in the clicked cell
        //highlight/unhighlight the close button as necessary
        NSRect iconRect = [cell closeButtonRectForFrame:cellFrame];

        if (_closeClicked && NSMouseInRect(trackingStartPoint, iconRect, [self isFlipped]) &&
                ([self allowsBackgroundTabClosing] || [[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]])) {
            [cell setCloseButtonPressed:NSMouseInRect(currentPoint, iconRect, [self isFlipped])];
            [self setNeedsDisplay];
            return;
        }

        float dx = fabs(currentPoint.x - trackingStartPoint.x);
        float dy = fabs(currentPoint.y - trackingStartPoint.y);
        float distance = sqrt(dx * dx + dy * dy);

        if (distance >= 10 && !_didDrag && ![[PSMTabDragAssistant sharedDragAssistant] isDragging] &&
                [[self delegate] respondsToSelector:@selector(tabView:shouldDragTabViewItem:fromTabBar:)] &&
                [[self delegate] tabView:_tabView shouldDragTabViewItem:[cell representedObject] fromTabBar:self]) {
            _didDrag = YES;
            [[PSMTabDragAssistant sharedDragAssistant] startDraggingCell:cell fromTabBar:self withMouseDownEvent:[self lastMouseDownEvent]];
        }
    }
}

- (void)otherMouseUp:(NSEvent *)theEvent
{
    // Middle click closes a tab, even if the click is not on the close button.
    if ([theEvent buttonNumber] == 2 && !_resizing) {
        NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
        NSRect cellFrame;
        PSMTabBarCell *cell = [self cellForPoint:mousePt cellFrame:&cellFrame];
        NSRect mouseDownCellFrame;
        PSMTabBarCell *mouseDownCell = [self cellForPoint:[self convertPoint:[[self lastMiddleMouseDownEvent] locationInWindow] fromView:nil]
                                                cellFrame:&mouseDownCellFrame];
        if (cell && cell == mouseDownCell) {
            [self closeTabClick:cell];
        }
    }
}

- (void)mouseUp:(NSEvent *)theEvent
{
    if (_resizing) {
        _resizing = NO;
        [[NSCursor arrowCursor] set];
    } else {
        // what cell?
        NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
        NSRect cellFrame, mouseDownCellFrame;
        PSMTabBarCell *cell = [self cellForPoint:mousePt cellFrame:&cellFrame];
        PSMTabBarCell *mouseDownCell = [self cellForPoint:[self convertPoint:[[self lastMouseDownEvent] locationInWindow] fromView:nil] cellFrame:&mouseDownCellFrame];
        if (cell) {
            NSPoint trackingStartPoint = [self convertPoint:[[self lastMouseDownEvent] locationInWindow] fromView:nil];
            NSRect iconRect = [mouseDownCell closeButtonRectForFrame:mouseDownCellFrame];

            if ((NSMouseInRect(mousePt, iconRect,[self isFlipped])) &&
                cell.closeButtonVisible &&
                [mouseDownCell closeButtonPressed]) {
                [self performSelector:@selector(closeTabClick:) withObject:cell];
            } else if (NSMouseInRect(mousePt,
                                     mouseDownCellFrame,
                                     [self isFlipped]) &&
                       (!NSMouseInRect(trackingStartPoint,
                                       [cell closeButtonRectForFrame:cellFrame],
                                       [self isFlipped]) ||
                        [self disableTabClose] ||
                        ![self allowsBackgroundTabClosing])) {
                [mouseDownCell setCloseButtonPressed:NO];
                [self performSelector:@selector(tabClick:) withObject:cell];
            } else {
                [mouseDownCell setCloseButtonPressed:NO];
                [self performSelector:@selector(tabNothing:) withObject:cell];
            }
        }

        _closeClicked = NO;
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    NSMenu *menu = nil;
    NSTabViewItem *item = [[self cellForPoint:[self convertPoint:[event locationInWindow] fromView:nil] cellFrame:nil] representedObject];

    if (item && [[self delegate] respondsToSelector:@selector(tabView:menuForTabViewItem:)]) {
        menu = [[self delegate] tabView:_tabView menuForTabViewItem:item];
    }
    else if (!item) {
        // when the "LSUIElement hack" (issue #954) is enabled, the menu bar is inaccessible,
        // so show it as a context menu when right-clicking empty tabBar region
        if ([[[NSBundle mainBundle] infoDictionary] objectForKey:@"LSUIElement"]) {
            menu = [NSApp mainMenu];
        }
    }
    return menu;
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    if ([self orientation] == PSMTabBarVerticalOrientation) {
        NSRect frame = [self frame];
        [self addCursorRect:NSMakeRect(frame.size.width - 2, 0, 2, frame.size.height) cursor:[NSCursor resizeLeftRightCursor]];
    }
}

#pragma mark -
#pragma mark Drag and Drop

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)theEvent
{
    return YES;
}

// NSDraggingSource
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
    return (isLocal ? NSDragOperationMove : NSDragOperationNone);
}

- (BOOL)ignoreModifierKeysWhileDragging
{
    return YES;
}

- (void)draggedImage:(NSImage *)anImage beganAt:(NSPoint)screenPoint
{
    [[PSMTabDragAssistant sharedDragAssistant] draggingBeganAt:screenPoint];
}

- (void)draggedImage:(NSImage *)image movedTo:(NSPoint)screenPoint
{
    [[PSMTabDragAssistant sharedDragAssistant] draggingMovedTo:screenPoint];
}

// NSDraggingDestination
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    if ([[[sender draggingPasteboard] types] indexOfObject:@"com.iterm2.psm.controlitem"] != NSNotFound) {
        if ([[self delegate] respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:)] &&
            ![[self delegate] tabView:[[sender draggingSource] tabView]
                shouldDropTabViewItem:[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject]
                             inTabBar:self]) {
            return NSDragOperationNone;
        }

        [[PSMTabDragAssistant sharedDragAssistant] draggingEnteredTabBar:self atPoint:[self convertPoint:[sender draggingLocation] fromView:nil]];
        return NSDragOperationMove;
    } else if ([[self delegate] respondsToSelector:@selector(tabView:draggingEnteredTabBarForSender:)]) {
        NSDragOperation op = [[self delegate] tabView:_tabView draggingEnteredTabBarForSender:sender];
        if (op != NSDragOperationNone) {
            [[PSMTabDragAssistant sharedDragAssistant] startAnimationWithOrientation:_orientation width:_cellOptimumWidth];
            [[PSMTabDragAssistant sharedDragAssistant] draggingEnteredTabBar:self atPoint:[self convertPoint:[sender draggingLocation] fromView:nil]];
        }
        return op;
    } else {
        return NSDragOperationNone;
    }
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
    PSMTabBarCell *cell = [self cellForPoint:[self convertPoint:[sender draggingLocation] fromView:nil] cellFrame:nil];

    if ([[[sender draggingPasteboard] types] indexOfObject:@"com.iterm2.psm.controlitem"] != NSNotFound) {

        if ([[self delegate] respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:)] &&
            ![[self delegate] tabView:[[sender draggingSource] tabView]
                shouldDropTabViewItem:[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject]
                             inTabBar:self]) {
            return NSDragOperationNone;
        }

        [[PSMTabDragAssistant sharedDragAssistant] draggingUpdatedInTabBar:self atPoint:[self convertPoint:[sender draggingLocation] fromView:nil]];
        return NSDragOperationMove;
    } else if ([[self delegate] respondsToSelector:@selector(tabView:shouldAcceptDragFromSender:)] &&
               [[self delegate] tabView:_tabView shouldAcceptDragFromSender:sender]) {
        [[PSMTabDragAssistant sharedDragAssistant] draggingUpdatedInTabBar:self atPoint:[self convertPoint:[sender draggingLocation] fromView:nil]];
        return NSDragOperationMove;
    } else if (cell) {
        //something that was accepted by the delegate was dragged on
        [_tabView selectTabViewItem:[cell representedObject]];
        return NSDragOperationCopy;
    }

    return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
    [[PSMTabDragAssistant sharedDragAssistant] draggingExitedTabBar:self];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
    // validate the drag operation only if there's a valid tab bar to drop into
    BOOL badType = [[[sender draggingPasteboard] types] indexOfObject:@"com.iterm2.psm.controlitem"] == NSNotFound;
    if (badType && [[self delegate] respondsToSelector:@selector(tabView:shouldAcceptDragFromSender:)] &&
        ![[self delegate] tabView:_tabView shouldAcceptDragFromSender:sender]) {
        badType = YES;
    }
    return badType ||
           [[PSMTabDragAssistant sharedDragAssistant] destinationTabBar] != nil;
}

- (BOOL)_delegateAcceptsSender:(id <NSDraggingInfo>)sender
{
    return [[self delegate] respondsToSelector:@selector(tabView:shouldAcceptDragFromSender:)] &&
           [[self delegate] tabView:_tabView shouldAcceptDragFromSender:sender];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    if ([[[sender draggingPasteboard] types] indexOfObject:@"com.iterm2.psm.controlitem"] != NSNotFound ||
        [self _delegateAcceptsSender:sender]) {
        [[PSMTabDragAssistant sharedDragAssistant] performDragOperation:sender];
    } else if ([[self delegate] respondsToSelector:@selector(tabView:acceptedDraggingInfo:onTabViewItem:)]) {
        //forward the drop to the delegate
        [[self delegate] tabView:_tabView acceptedDraggingInfo:sender onTabViewItem:[[self cellForPoint:[self convertPoint:[sender draggingLocation] fromView:nil] cellFrame:nil] representedObject]];
    }
    return YES;
}

- (void)draggedImage:(NSImage *)anImage endedAt:(NSPoint)aPoint operation:(NSDragOperation)operation
{
    if (operation != NSDragOperationNone) {
        [self removeTabForCell:[[PSMTabDragAssistant sharedDragAssistant] draggedCell]];
        [[PSMTabDragAssistant sharedDragAssistant] finishDrag];
    } else {
        [[PSMTabDragAssistant sharedDragAssistant] draggedImageEndedAt:aPoint operation:operation];
    }
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{

}

#pragma mark -
#pragma mark Actions

- (void)overflowMenuAction:(id)sender {
    [_tabView selectTabViewItem:[sender representedObject]];
    [self update];
}

- (void)closeTabClick:(id)sender
{
    NSTabViewItem *item = [sender representedObject];
    [[sender retain] autorelease];
    [[item retain] autorelease];

    if ([[self delegate] respondsToSelector:@selector(tabView:shouldCloseTabViewItem:)]){
        if (![[self delegate] tabView:_tabView shouldCloseTabViewItem:item]){
            // fix mouse downed close button
            [sender setCloseButtonPressed:NO];
            return;
        }
    }

    if ([[self delegate] respondsToSelector:@selector(closeTab:)]) {
        [[self delegate] closeTab:[item identifier]];
    }
}

- (void)tabClick:(id)sender {
    [_tabView selectTabViewItem:[sender representedObject]];
    [self update];
}

- (void)tabDoubleClick:(id)sender {
    if ([[self delegate] respondsToSelector:@selector(tabView:doubleClickTabViewItem:)]) {
        [[self delegate] tabView:[self tabView] doubleClickTabViewItem:[sender representedObject]];
    }
}

- (void)tabBarDoubleClick {
    if ([[self delegate] respondsToSelector:@selector(tabViewDoubleClickTabBar:)]) {
        [[self delegate] tabViewDoubleClickTabBar:[self tabView]];
    }
}

- (void)tabNothing:(id)sender {
    [self update];  // takes care of highlighting based on state
}

- (void)frameDidChange:(NSNotification *)notification {
    //figure out if the new frame puts the control in the way of the resize widget
    NSRect resizeWidgetFrame = [[[self window] contentView] frame];
    resizeWidgetFrame.origin.x += resizeWidgetFrame.size.width - 22;
    resizeWidgetFrame.size.width = 22;
    resizeWidgetFrame.size.height = 22;

    if ([[self window] showsResizeIndicator] && NSIntersectsRect([self frame], resizeWidgetFrame)) {
        //the resize widgets are larger on metal windows
        _resizeAreaCompensation = [[self window] styleMask] & NSTexturedBackgroundWindowMask ? 20 : 8;
    } else {
        _resizeAreaCompensation = 0;
    }

    [self update];
    // trying to address the drawing artifacts for the progress indicators - hackery follows
    // this one fixes the "blanking" effect when the control hides and shows itself
    for (PSMTabBarCell *cell in _cells) {
        [[cell indicator] setAnimate:NO];
        [[cell indicator] setAnimate:YES];
    }
    [self setNeedsDisplay];
}

- (void)viewWillStartLiveResize {
    for (PSMTabBarCell *cell in _cells) {
        [[cell indicator] setAnimate:NO];
    }
    [self setNeedsDisplay];
}

-(void)viewDidEndLiveResize {
    for (PSMTabBarCell *cell in _cells) {
        [[cell indicator] setAnimate:YES];
    }
    [self setNeedsDisplay];
}

- (void)windowDidMove:(NSNotification *)aNotification {
    [self setNeedsDisplay];
}

- (void)windowStatusDidChange:(NSNotification *)notification {
    // hide? must readjust things if I'm not supposed to be showing
    // this block of code only runs when the app launches
    if ([self hideForSingleTab] && ([_cells count] <= 1) && !_awakenedFromNib) {
        // must adjust frames now before display
        NSRect myFrame = [self frame];
        if ([self orientation] == PSMTabBarHorizontalOrientation) {
            if (partnerView) {
                NSRect partnerFrame = [partnerView frame];
                // above or below me?
                if (myFrame.origin.y - 22 > [partnerView frame].origin.y) {
                    // partner is below me
                    [self setFrame:NSMakeRect(myFrame.origin.x, myFrame.origin.y + 21, myFrame.size.width, myFrame.size.height - 21)];
                    [partnerView setFrame:NSMakeRect(partnerFrame.origin.x, partnerFrame.origin.y, partnerFrame.size.width, partnerFrame.size.height + 21)];
                } else {
                    // partner is above me
                    [self setFrame:NSMakeRect(myFrame.origin.x, myFrame.origin.y, myFrame.size.width, myFrame.size.height - 21)];
                    [partnerView setFrame:NSMakeRect(partnerFrame.origin.x, partnerFrame.origin.y - 21, partnerFrame.size.width, partnerFrame.size.height + 21)];
                }
                [partnerView setNeedsDisplay:YES];
                [self setNeedsDisplay];
            } else {
                // for window movement
                NSRect windowFrame = [[self window] frame];
                [[self window] setFrame:NSMakeRect(windowFrame.origin.x, windowFrame.origin.y + 21, windowFrame.size.width, windowFrame.size.height - 21) display:YES];
                [self setFrame:NSMakeRect(myFrame.origin.x, myFrame.origin.y, myFrame.size.width, myFrame.size.height - 21)];
            }
        } else {
            if (partnerView) {
                NSRect partnerFrame = [partnerView frame];
                //to the left or right?
                if (myFrame.origin.x < [partnerView frame].origin.x){
                    // partner is to the left
                    [self setFrame:NSMakeRect(myFrame.origin.x, myFrame.origin.y, 1, myFrame.size.height)];
                    [partnerView setFrame:NSMakeRect(partnerFrame.origin.x - myFrame.size.width + 1, partnerFrame.origin.y, partnerFrame.size.width + myFrame.size.width - 1, partnerFrame.size.height)];
                } else {
                    // partner to the right
                    [self setFrame:NSMakeRect(myFrame.origin.x + myFrame.size.width, myFrame.origin.y, 1, myFrame.size.height)];
                    [partnerView setFrame:NSMakeRect(partnerFrame.origin.x, partnerFrame.origin.y, partnerFrame.size.width + myFrame.size.width, partnerFrame.size.height)];
                }
                _tabBarWidth = myFrame.size.width;
                [partnerView setNeedsDisplay:YES];
                [self setNeedsDisplay];
            } else {
                // for window movement
                NSRect windowFrame = [[self window] frame];
                [[self window] setFrame:NSMakeRect(windowFrame.origin.x + myFrame.size.width - 1, windowFrame.origin.y, windowFrame.size.width - myFrame.size.width + 1, windowFrame.size.height) display:YES];
                [self setFrame:NSMakeRect(myFrame.origin.x, myFrame.origin.y, 1, myFrame.size.height)];
            }
        }

        _isHidden = YES;

        if ([[self delegate] respondsToSelector:@selector(tabView:tabBarDidHide:)]) {
            [[self delegate] tabView:[self tabView] tabBarDidHide:self];
        }
    }

    [self setNeedsDisplay];
     _awakenedFromNib = YES;
    [self update];
}

#pragma mark -
#pragma mark Menu Validation

- (BOOL)validateMenuItem:(NSMenuItem *)sender {
    return [[self delegate] respondsToSelector:@selector(tabView:validateOverflowMenuItem:forTabViewItem:)] ?
        [[self delegate] tabView:[self tabView] validateOverflowMenuItem:sender forTabViewItem:[sender representedObject]] : YES;
}

#pragma mark -
#pragma mark NSTabView Delegate

- (void)tabView:(NSTabView *)aTabView willAddTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:willAddTabViewItem:)]){
        [[self delegate] tabView:aTabView willAddTabViewItem:tabViewItem];
    }
}

- (void)tabView:(NSTabView *)aTabView willInsertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int)anIndex {
    if ([[self delegate] respondsToSelector:@selector(tabView:willInsertTabViewItem:atIndex:)]) {
        [[self delegate] tabView:aTabView willInsertTabViewItem:tabViewItem atIndex:anIndex];
    }
}

- (void)tabView:(NSTabView *)aTabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:willRemoveTabViewItem:)]) {
        [[self delegate] tabView:aTabView willRemoveTabViewItem:tabViewItem];
    }
}


- (void)tabView:(NSTabView *)aTabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    // here's a weird one - this message is sent before the "aDidChangeNumberOfTabViewItems"
    // message, thus I can end up updating when there are no cells, if no tabs were (yet) present
    if ([_cells count] > 0) {
        [self update];
    }
    if ([[self delegate] respondsToSelector:@selector(tabView:didSelectTabViewItem:)]) {
        [[self delegate] tabView:aTabView didSelectTabViewItem:tabViewItem];
    }

    NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
}

- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem {
}

- (BOOL)tabView:(NSTabView *)aTabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:shouldSelectTabViewItem:)]) {
        return (BOOL)[[self delegate] tabView:aTabView shouldSelectTabViewItem:tabViewItem];
    } else {
        return YES;
    }
}

- (void)tabView:(NSTabView *)aTabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:willSelectTabViewItem:)]) {
        [[self delegate] tabView:aTabView willSelectTabViewItem:tabViewItem];
    }
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)aTabView {
    NSArray *tabItems = [_tabView tabViewItems];
    // go through cells, remove any whose representedObjects are not in [tabView tabViewItems]
    NSMutableArray *cellsToRemove = [NSMutableArray array];
    for (PSMTabBarCell *cell in _cells) {
        if (![tabItems containsObject:[cell representedObject]]) {
            [cellsToRemove addObject:cell];
        }
    }
    for (PSMTabBarCell *cell in cellsToRemove) {
        if ([[self delegate] respondsToSelector:@selector(tabView:didCloseTabViewItem:)]) {
            [[self delegate] tabView:aTabView didCloseTabViewItem:[cell representedObject]];
        }

        [self removeTabForCell:cell];
    }

    // go through tab view items, add cell for any not present
    NSMutableArray *cellItems = [self representedTabViewItems];
    int i = 0;
    for (NSTabViewItem *item in tabItems) {
        if (![cellItems containsObject:item]) {
            [self addTabViewItem:item atIndex:i];
        }
        i++;
    }

    // pass along for other delegate responses
    if ([[self delegate] respondsToSelector:@selector(tabViewDidChangeNumberOfTabViewItems:)]) {
        [[self delegate] tabViewDidChangeNumberOfTabViewItems:aTabView];
    }
}

- (NSDragOperation)tabView:(NSTabView *)tabView draggingEnteredTabBarForSender:(id<NSDraggingInfo>)tagViewItem {
    return NSDragOperationNone;
}

- (BOOL)tabView:(NSTabView *)tabView shouldAcceptDragFromSender:(id<NSDraggingInfo>)tagViewItem {
    return NO;
}

- (NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id <NSDraggingInfo>)sender {
    return nil;
}

#pragma mark -
#pragma mark Tooltips

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)userData
{
    if ([[self delegate] respondsToSelector:@selector(tabView:toolTipForTabViewItem:)]) {
        return [[self delegate] tabView:[self tabView] toolTipForTabViewItem:[[self cellForPoint:point cellFrame:nil] representedObject]];
    }
    return nil;
}

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [super encodeWithCoder:aCoder];
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:_cells forKey:@"PSMcells"];
        [aCoder encodeObject:_tabView forKey:@"PSMtabView"];
        [aCoder encodeObject:_overflowPopUpButton forKey:@"PSMoverflowPopUpButton"];
        [aCoder encodeObject:_addTabButton forKey:@"PSMaddTabButton"];
        [aCoder encodeObject:_style forKey:@"PSMstyle"];
        [aCoder encodeInt:_orientation forKey:@"PSMorientation"];
        [aCoder encodeBool:_disableTabClose forKey:@"PSMdisableTabClose"];
        [aCoder encodeBool:_hideForSingleTab forKey:@"PSMhideForSingleTab"];
        [aCoder encodeBool:_allowsBackgroundTabClosing forKey:@"PSMallowsBackgroundTabClosing"];
        [aCoder encodeBool:_allowsResizing forKey:@"PSMallowsResizing"];
        [aCoder encodeBool:_selectsTabsOnMouseDown forKey:@"PSMselectsTabsOnMouseDown"];
        [aCoder encodeBool:_showAddTabButton forKey:@"PSMshowAddTabButton"];
        [aCoder encodeBool:_sizeCellsToFit forKey:@"PSMsizeCellsToFit"];
        [aCoder encodeInt:_cellMinWidth forKey:@"PSMcellMinWidth"];
        [aCoder encodeInt:_cellMaxWidth forKey:@"PSMcellMaxWidth"];
        [aCoder encodeInt:_cellOptimumWidth forKey:@"PSMcellOptimumWidth"];
        [aCoder encodeInt:_currentStep forKey:@"PSMcurrentStep"];
        [aCoder encodeBool:_isHidden forKey:@"PSMisHidden"];
        [aCoder encodeBool:_hideIndicators forKey:@"PSMhideIndicators"];
        [aCoder encodeObject:partnerView forKey:@"PSMpartnerView"];
        [aCoder encodeBool:_awakenedFromNib forKey:@"PSMawakenedFromNib"];
        [aCoder encodeObject:_lastMouseDownEvent forKey:@"PSMlastMouseDownEvent"];
        [aCoder encodeObject:_lastMiddleMouseDownEvent forKey:@"PSMlastMiddleMouseDownEvent"];
        [aCoder encodeObject:_delegate forKey:@"PSMdelegate"];
        [aCoder encodeBool:_useOverflowMenu forKey:@"PSMuseOverflowMenu"];
        [aCoder encodeBool:_automaticallyAnimates forKey:@"PSMautomaticallyAnimates"];

    }
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        if ([aDecoder allowsKeyedCoding]) {
            _cells = [[aDecoder decodeObjectForKey:@"PSMcells"] retain];
            _tabView = [[aDecoder decodeObjectForKey:@"PSMtabView"] retain];
            _overflowPopUpButton = [[aDecoder decodeObjectForKey:@"PSMoverflowPopUpButton"] retain];
            _addTabButton = [[aDecoder decodeObjectForKey:@"PSMaddTabButton"] retain];
            _style = [[aDecoder decodeObjectForKey:@"PSMstyle"] retain];
            _orientation = [aDecoder decodeIntForKey:@"PSMorientation"];
            _disableTabClose = [aDecoder decodeBoolForKey:@"PSMdisableTabClose"];
            _hideForSingleTab = [aDecoder decodeBoolForKey:@"PSMhideForSingleTab"];
            _allowsBackgroundTabClosing = [aDecoder decodeBoolForKey:@"PSMallowsBackgroundTabClosing"];
            _allowsResizing = [aDecoder decodeBoolForKey:@"PSMallowsResizing"];
            _selectsTabsOnMouseDown = [aDecoder decodeBoolForKey:@"PSMselectsTabsOnMouseDown"];
            _showAddTabButton = [aDecoder decodeBoolForKey:@"PSMshowAddTabButton"];
            _sizeCellsToFit = [aDecoder decodeBoolForKey:@"PSMsizeCellsToFit"];
            _cellMinWidth = [aDecoder decodeIntForKey:@"PSMcellMinWidth"];
            _cellMaxWidth = [aDecoder decodeIntForKey:@"PSMcellMaxWidth"];
            _cellOptimumWidth = [aDecoder decodeIntForKey:@"PSMcellOptimumWidth"];
            _currentStep = [aDecoder decodeIntForKey:@"PSMcurrentStep"];
            _isHidden = [aDecoder decodeBoolForKey:@"PSMisHidden"];
            _hideIndicators = [aDecoder decodeBoolForKey:@"PSMhideIndicators"];
            partnerView = [[aDecoder decodeObjectForKey:@"PSMpartnerView"] retain];
            _awakenedFromNib = [aDecoder decodeBoolForKey:@"PSMawakenedFromNib"];
            _lastMouseDownEvent = [[aDecoder decodeObjectForKey:@"PSMlastMouseDownEvent"] retain];
            _lastMiddleMouseDownEvent = [[aDecoder decodeObjectForKey:@"PSMlastMiddleMouseDownEvent"] retain];
            _useOverflowMenu = [aDecoder decodeBoolForKey:@"PSMuseOverflowMenu"];
            _automaticallyAnimates = [aDecoder decodeBoolForKey:@"PSMautomaticallyAnimates"];
            _delegate = [[aDecoder decodeObjectForKey:@"PSMdelegate"] retain];
        }
    }
    return self;
}

#pragma mark -
#pragma mark IB Palette

- (NSSize)minimumFrameSizeFromKnobPosition:(int)position {
    return NSMakeSize(100.0, 22.0);
}

- (NSSize)maximumFrameSizeFromKnobPosition:(int)knobPosition {
    return NSMakeSize(10000.0, 22.0);
}

- (void)placeView:(NSRect)newFrame {
    // this is called any time the view is resized in IB
    [self setFrame:newFrame];
    [self update];
}

- (void)changeIdentifier:(id)newIdentifier atIndex:(int)theIndex {
    NSTabViewItem *tabViewItem = [_tabView tabViewItemAtIndex:theIndex];
    assert(tabViewItem);
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            [tabViewItem setIdentifier:newIdentifier];
            return;
        }
    }
    assert(false);
}

#pragma mark -
#pragma mark Convenience

- (PSMTabBarCell *)cellWithIdentifier:(id)identifier {
    for (PSMTabBarCell *cell in _cells) {
        if ([cell.representedObject identifier] == identifier) {
            return cell;
        }
    }
    return nil;
}

- (void)setIsProcessing:(BOOL)isProcessing forTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    cell.indicator.hidden = !isProcessing;
    cell.indicator.animate = isProcessing;
}

- (void)setIcon:(NSImage *)icon forTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    cell.hasIcon = (icon != nil);
}

- (void)setObjectCount:(NSInteger)objectCount forTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    cell.count = objectCount;
}

- (void)initializeStateForCell:(PSMTabBarCell *)cell {
    [[cell indicator] setHidden:YES];
    [cell setHasIcon:NO];
    [cell setCount:0];
}

- (void)bindPropertiesForCell:(PSMTabBarCell *)cell andTabViewItem:(NSTabViewItem *)item {
    // bind my string value to the label on the represented tab
    [cell bind:@"title" toObject:item withKeyPath:@"label" options:nil];
    [_delegate tabView:_tabView updateStateForTabViewItem:item];
}

- (NSMutableArray *)representedTabViewItems {
    NSMutableArray *temp = [NSMutableArray arrayWithCapacity:[_cells count]];
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject]) {
            [temp addObject:[cell representedObject]];
        }
    }
    return temp;
}

- (id)cellForPoint:(NSPoint)point cellFrame:(NSRectPointer)outFrame
{
    if ([self orientation] == PSMTabBarHorizontalOrientation && !NSPointInRect(point, [self genericCellRect])) {
        return nil;
    }

    int i, cnt = [_cells count];
    for (i = 0; i < cnt; i++) {
        PSMTabBarCell *cell = [_cells objectAtIndex:i];

        if (NSPointInRect(point, [cell frame])) {
            if (outFrame) {
                *outFrame = [cell frame];
            }
            return cell;
        }
    }
    return nil;
}

- (PSMTabBarCell *)lastVisibleTab
{
    int i, cellCount = [_cells count];
    for(i = 0; i < cellCount; i++){
        if ([[_cells objectAtIndex:i] isInOverflowMenu])
            return [_cells objectAtIndex:(i-1)];
    }
    return [_cells objectAtIndex:(cellCount - 1)];
}

- (int)numberOfVisibleTabs
{
    int i, cellCount = [_cells count];
    for(i = 0; i < cellCount; i++){
        if ([[_cells objectAtIndex:i] isInOverflowMenu]) {
            return i;
        }
    }
    return cellCount;
}

#pragma mark -
#pragma mark Accessibility

-(BOOL)accessibilityIsIgnored {
    return NO;
}

- (NSArray*)accessibilityAttributeNames
{
    static NSArray *attributes = nil;
    if (!attributes) {
        NSSet *set = [NSSet setWithArray:[super accessibilityAttributeNames]];
        set = [set setByAddingObjectsFromArray:[NSArray arrayWithObjects:
                                                NSAccessibilityTabsAttribute,
                                                NSAccessibilityValueAttribute,
                                                nil]];
        attributes = [[set allObjects] retain];
    }
    return attributes;
}

- (id)accessibilityAttributeValue:(NSString *)attribute {
    id attributeValue = nil;
    if ([attribute isEqualToString: NSAccessibilityRoleAttribute]) {
        attributeValue = NSAccessibilityTabGroupRole;
    } else if ([attribute isEqualToString: NSAccessibilityChildrenAttribute]) {
        NSMutableArray *children = [NSMutableArray arrayWithArray:[_cells objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self numberOfVisibleTabs])]]];
        if (![_overflowPopUpButton isHidden]) {
            [children addObject:_overflowPopUpButton];
        }
        if (![_addTabButton isHidden]) {
            [children addObject:_addTabButton];
        }
        attributeValue = NSAccessibilityUnignoredChildren(children);
    } else if ([attribute isEqualToString: NSAccessibilityTabsAttribute]) {
        attributeValue = NSAccessibilityUnignoredChildren(_cells);
    } else if ([attribute isEqualToString:NSAccessibilityValueAttribute]) {
        NSTabViewItem *tabViewItem = [_tabView selectedTabViewItem];
        for (NSActionCell *cell in _cells) {
            if ([cell representedObject] == tabViewItem)
                attributeValue = cell;
        }
        if (!attributeValue)
        {
            NSLog(@"WARNING: seems no tab cell is currently selected");
        }
    } else {
        attributeValue = [super accessibilityAttributeValue:attribute];
    }
    return attributeValue;
}

- (id)accessibilityHitTest:(NSPoint)point {
    id hitTestResult = self;

    for (PSMTabBarCell *cell in _cells) {
        if ([cell isHighlighted]) {
            hitTestResult = [cell accessibilityHitTest:point];
            break;
        }
    }

    return hitTestResult;
}

#pragma mark - iTerm Add On

- (void)setTabColor:(NSColor *)aColor forTabViewItem:(NSTabViewItem *)tabViewItem {
    BOOL updated = NO;

    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            if ([cell tabColor] != aColor) {
                updated = YES;
                [cell setTabColor: aColor];
            }
        }
    }

    if (updated) {
        [self update: NO];
    }
}

- (NSColor*)tabColorForTabViewItem:(NSTabViewItem*)tabViewItem {
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            return [cell tabColor];
        }
    }
    return nil;
}

- (void)modifierChanged:(NSNotification *)aNotification {
    int mask = ([[[aNotification userInfo] objectForKey:kPSMTabModifierKey] intValue]);
    [self setModifier:mask];
}

- (NSString*)_modifierString {
    NSString *str = @"";
    if (_modifier & NSCommandKeyMask) {
        str = [NSString stringWithFormat:@"⌘%@", str];
    }
    if (_modifier & NSShiftKeyMask) {
        str = [NSString stringWithFormat:@"⇧%@", str];
    }
    if (_modifier & NSAlternateKeyMask) {
        str = [NSString stringWithFormat:@"⌥%@", str];
    }
    if (_modifier & NSControlKeyMask) {
        str = [NSString stringWithFormat:@"^%@", str];
    }
    return str;
}

- (void)setModifier:(int)mask {
    _modifier = mask;
    NSString *str = [self _modifierString];

    for (PSMTabBarCell *cell in _cells) {
        [cell setModifierString:str];
    }
    [self setNeedsDisplay];
}

- (void)fillPath:(NSBezierPath*)path {
  [_style fillPath:path];
}

- (NSColor *)accessoryTextColor {
    return [_style accessoryTextColor] ?: [NSColor blackColor];
}

- (void)setTabsHaveCloseButtons:(BOOL)tabsHaveCloseButtons {
    _hasCloseButton = tabsHaveCloseButtons;

    for (PSMTabBarCell *cell in _cells) {
        [cell setHasCloseButton:tabsHaveCloseButtons];
    }
}

#pragma mark - NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    switch (context) {
        case NSDraggingContextWithinApplication:
            return NSDragOperationEvery;

        case NSDraggingContextOutsideApplication:
        default:
            return NSDragOperationNone;
    }
}

#pragma mark - PSMProgressIndicatorDelegate

- (void)progressIndicatorNeedsUpdate {
    [self update];
}

@end
