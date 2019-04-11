//
//  iTermBadgeConfigurationWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/21/19.
//

#import "iTermAdvancedSettingsModel.h"
#import "iTermBadgeConfigurationWindowController.h"
#import "iTermFontPanel.h"
#import "ITAddressBookMgr.h"
#import "iTermBadgeLabel.h"
#import "iTermProfilePreferences.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import <BetterFontPicker/BetterFontPicker-Swift.h>

static const CGFloat iTermBadgeConfigurationBadgeViewInset = 3;

@interface iTermBadgeConfigurationWindow : NSWindow
@end

@implementation iTermBadgeConfigurationWindow
@end

@protocol iTermBadgeConfigurationBadgeViewDelegate<NSObject>
- (void)badgeViewFrameDidChange:(NSRect)frame;
- (Profile *)badgeViewProfile;
- (NSFont *)badgeViewFont;
@end

@interface iTermBadgeConfigurationBadgeView : NSBox<iTermBadgeLabelDelegate>
@property (nonatomic, weak) id<iTermBadgeConfigurationBadgeViewDelegate> delegate;
@end

typedef struct {
    CGFloat minX;
    CGFloat maxX;
    CGFloat minY;
    CGFloat maxY;
    SEL selector;
    NSCursor *cursor;
} iTermBadgeViewEdge;

@implementation iTermBadgeConfigurationBadgeView {
    BOOL _dragging;
    SEL _selector;
    NSPoint _point;
    iTermBadgeViewEdge _edges[4];
    NSTrackingArea *_trackingArea;
    IBOutlet NSImageView *_loremIpsum;
    iTermBadgeLabel *_badge;
    NSColor *_borderColor;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
    self = [super initWithCoder:decoder];
    if (self) {
        _badge = [[iTermBadgeLabel alloc] init];
        _badge.minimumPointSize = 1;
        _badge.maximumPointSize = 200;
        _badge.delegate = self;
        _badge.fillColor = [NSColor blackColor];
        _badge.backgroundColor = [NSColor redColor];
        _badge.stringValue = @"Lorem ipsum dolor sit amet";
    }
    return self;
}

- (void)awakeFromNib {
    _badge.viewSize = self.bounds.size;
}

- (void)setDelegate:(id<iTermBadgeConfigurationBadgeViewDelegate>)delegate {
    _delegate = delegate;
    if (delegate) {
        _badge.fillColor = [[[iTermProfilePreferences objectForKey:KEY_BADGE_COLOR inProfile:[delegate badgeViewProfile]] colorValue] colorWithAlphaComponent:1];
        _badge.backgroundColor = [NSColor clearColor];
        _loremIpsum.image = [_badge image];
        NSColor *backgroundColor = [[iTermProfilePreferences objectForKey:KEY_BACKGROUND_COLOR inProfile:[delegate badgeViewProfile]] colorValue];
        if (backgroundColor.perceivedBrightness > 0.5) {
            _borderColor = [NSColor blackColor];
        } else {
            _borderColor = [NSColor whiteColor];
        }
        [self layoutSubviews];
    }
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateTrackingAreas];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }


    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingMouseEnteredAndExited |
                                                          NSTrackingMouseMoved |
                                                          NSTrackingCursorUpdate |
                                                          NSTrackingActiveAlways) owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (iTermBadgeViewEdge)edge:(int)i {
    const CGFloat radius = self.radius;
    const CGFloat width = self.bounds.size.width;
    const CGFloat height = self.bounds.size.height;
    iTermBadgeViewEdge edges[4] = {
        { 0,                  radius * 2,     0,                   height,     @selector(adjustLeft:),   [NSCursor resizeLeftRightCursor] },
        { width - radius * 2, width,          0,                   height,     @selector(adjustRight:),  [NSCursor resizeLeftRightCursor] },
        { 0,                  width,          height - radius * 2, height,     @selector(adjustTop:),    [NSCursor resizeUpDownCursor] },
        { 0,                  width,          0,                   radius * 2, @selector(adjustBottom:), [NSCursor resizeUpDownCursor] }
    };
    return edges[i];
}

// I tried like hell to use resetCursorRects but it just doesn't get called.

- (void)mouseEntered:(NSEvent *)event {
    [self setCursorForMouseAtPointInWindow:event.locationInWindow];
}

- (void)mouseExited:(NSEvent *)event {
    [self setCursorForMouseAtPointInWindow:event.locationInWindow];
}

- (void)mouseMoved:(NSEvent *)event {
    [self setCursorForMouseAtPointInWindow:event.locationInWindow];
}

- (void)setCursorForMouseAtPointInWindow:(NSPoint)point {
    if (_selector) {
        [[NSCursor closedHandCursor] set];
        return;
    }
    iTermBadgeViewEdge edge = [self edgeAtPoint:point];
    if (edge.cursor) {
        [edge.cursor set];
    } else {
        [[NSCursor arrowCursor] set];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [_borderColor set];
    NSRect rect = NSInsetRect(self.bounds, self.radius, self.radius);
    NSRect superviewsFrameInMyCoords = [self.superview convertRect:self.superview.bounds toView:self];
    rect = NSIntersectionRect(rect, NSInsetRect(superviewsFrameInMyCoords, 1, 1));
    NSFrameRect(rect);

    const CGFloat boxRadius = 3;
    const CGFloat inset = iTermBadgeConfigurationBadgeViewInset;
    const NSSize mySize = self.bounds.size;
    const CGFloat centerX = mySize.width / 2;
    const CGFloat top = mySize.height - inset;
    const CGFloat bottom = 0;
    const CGFloat left = 0;
    const CGFloat right = mySize.width - inset;
    const CGFloat centerY = mySize.height / 2;
    NSRect boxes[] = {
        NSMakeRect(centerX - boxRadius, top - boxRadius, boxRadius * 2, boxRadius * 2),
        NSMakeRect(centerX - boxRadius, bottom, boxRadius * 2, boxRadius * 2),
        NSMakeRect(left, centerY - boxRadius, boxRadius * 2, boxRadius * 2),
        NSMakeRect(right - boxRadius, centerY - boxRadius, boxRadius * 2, boxRadius * 2),
    };
    for (int i = 0; i < 4; i++) {
        [[NSColor whiteColor] set];
        NSRectFill(boxes[i]);

        [_borderColor set];
        NSFrameRect(boxes[i]);
    }
}

- (CGFloat)radius {
    return iTermBadgeConfigurationBadgeViewInset;
}

- (iTermBadgeViewEdge)edgeAtPoint:(NSPoint)locationInWindow {
    const NSPoint point = [self convertPoint:locationInWindow fromView:nil];
    for (int i = 0; i < 4; i++) {
        iTermBadgeViewEdge edge = [self edge:i];
        if (point.x >= edge.minX &&
            point.x < edge.maxX &&
            point.y >= edge.minY &&
            point.y < edge.maxY) {
            return edge;
        }
    }
    iTermBadgeViewEdge bogus = { 0 };
    return bogus;
}

- (void)mouseDown:(NSEvent *)event {
    _point = event.locationInWindow;
    iTermBadgeViewEdge edge = [self edgeAtPoint:event.locationInWindow];
    _selector = edge.selector;
    if (_selector) {
        [[NSCursor closedHandCursor] set];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_selector) {
        return;
    }
    const NSPoint point = event.locationInWindow;
    const NSSize delta = NSMakeSize(point.x - _point.x,
                                    point.y - _point.y);
    _point = point;
    [self it_performNonObjectReturningSelector:_selector withObject:[NSValue valueWithSize:delta]];
    [[NSCursor closedHandCursor] set];
}

- (void)mouseUp:(NSEvent *)event {
    _selector = nil;
}

- (void)adjustLeft:(NSValue *)value {
    const NSSize delta = value.sizeValue;
    NSRect frame = self.frame;
    const CGFloat proposal = frame.origin.x + delta.width;
    const CGFloat upperBound = NSMaxX(frame) - 16;
    const CGFloat lowerBound = -iTermBadgeConfigurationBadgeViewInset;
    const CGFloat newValue = MAX(lowerBound, MIN(upperBound, proposal));
    const CGFloat validatedDelta = newValue - frame.origin.x;

    frame.origin.x = newValue;
    frame.size.width -= validatedDelta;
    self.frame = frame;
    _point = [self.superview convertPoint:NSMakePoint(NSMinX(frame), _point.y) toView:nil];
}

- (void)adjustRight:(NSValue *)value {
    const NSSize delta = value.sizeValue;
    NSRect frame = self.frame;
    const CGFloat proposedRight = NSMaxX(frame) + delta.width;
    const CGFloat upperBound = NSWidth(self.superview.bounds) + iTermBadgeConfigurationBadgeViewInset;
    const CGFloat lowerBound = NSMinX(frame) + 16;
    const CGFloat newValue = MAX(lowerBound, MIN(upperBound, proposedRight));
    const CGFloat safeDeltaWidth = newValue - NSMaxX(frame);

    frame.size.width += safeDeltaWidth;

    self.frame = frame;
    _point = [self.superview convertPoint:NSMakePoint(NSMaxX(frame), _point.y) toView:nil];
}

- (void)adjustTop:(NSValue *)value {
    const NSSize delta = value.sizeValue;
    NSRect frame = self.frame;
    const CGFloat proposedTop = NSMaxY(frame) + delta.height;
    const CGFloat upperBound = NSHeight(self.superview.bounds) + iTermBadgeConfigurationBadgeViewInset;
    const CGFloat lowerBound = NSMinY(frame) + 16;
    const CGFloat newValue = MAX(lowerBound, MIN(upperBound, proposedTop));
    const CGFloat safeDeltaHeight = newValue - NSMaxY(frame);

    frame.size.height += safeDeltaHeight;

    self.frame = frame;
    _point = [self.superview convertPoint:NSMakePoint(_point.x, NSMaxY(frame)) toView:nil];
}

- (void)adjustBottom:(NSValue *)value {
    const NSSize delta = value.sizeValue;
    NSRect frame = self.frame;
    const CGFloat proposal = frame.origin.y + delta.height;
    const CGFloat upperBound = NSMaxY(frame) - 16;
    const CGFloat lowerBound = -iTermBadgeConfigurationBadgeViewInset;
    const CGFloat newValue = MAX(lowerBound, MIN(upperBound, proposal));
    const CGFloat validatedDelta = newValue - frame.origin.y;

    frame.origin.y = newValue;
    frame.size.height -= validatedDelta;
    self.frame = frame;
    _point = [self.superview convertPoint:NSMakePoint(_point.x, NSMinY(frame)) toView:nil];
}

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [self.delegate badgeViewFrameDidChange:frame];
    [self setNeedsDisplay:YES];
}

- (void)updateImageViewFrame {
    NSRect myFrame = NSInsetRect(self.bounds, 6, 6);
    if (_loremIpsum.image.size.height == 0 || myFrame.size.height == 0) {
        _loremIpsum.frame = myFrame;
    }
    CGFloat imageAspectRatio = _loremIpsum.image.size.width / _loremIpsum.image.size.height;
    CGFloat myAspectRatio = myFrame.size.width / myFrame.size.height;
    if (imageAspectRatio > myAspectRatio) {
        // image is wider
        _loremIpsum.frame = NSMakeRect(myFrame.origin.x,
                                       myFrame.origin.y + myFrame.size.height - (myFrame.size.width / imageAspectRatio),
                                       myFrame.size.width,
                                       myFrame.size.width / imageAspectRatio);
    } else {
        // image is taller
        _loremIpsum.frame = NSMakeRect(myFrame.size.width - (myFrame.size.height * imageAspectRatio),
                                       0,
                                       myFrame.size.height * imageAspectRatio,
                                       myFrame.size.height);
    }
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutSubviews];
}

- (void)layoutSubviews {
    _badge.dirty = YES;
    _badge.viewSize = NSMakeSize(self.bounds.size.width * 2,
                                 self.bounds.size.height * 2);
    _loremIpsum.image = [_badge image];
    [self updateImageViewFrame];
}

- (void)reload {
    _badge.dirty = YES;
    _loremIpsum.image = [_badge image];
    [self updateImageViewFrame];
}

#pragma mark - iTermBadgeLabelDelegate

- (NSFont *)badgeLabelFontOfSize:(CGFloat)pointSize {
    NSFont *font = [self.delegate badgeViewFont];
    return [NSFont fontWithName:font.fontName size:pointSize];
}

- (NSSize)badgeLabelSizeFraction {
    Profile *profile = [self.delegate badgeViewProfile];
    const CGFloat width = [iTermProfilePreferences floatForKey:KEY_BADGE_MAX_WIDTH inProfile:profile];
    const CGFloat height = [iTermProfilePreferences floatForKey:KEY_BADGE_MAX_HEIGHT inProfile:profile];
    return NSMakeSize(width, height);
}

@end

@interface iTermBadgeConfigurationWindowController ()<iTermBadgeConfigurationBadgeViewDelegate, NSTextFieldDelegate, BFPCompositeViewDelegate>
@property (nonatomic, strong) IBOutlet NSTextField *maxWidthTextField;
@property (nonatomic, strong) IBOutlet NSTextField *maxHeightTextField;
@property (nonatomic, strong) IBOutlet NSTextField *rightMarginTextField;
@property (nonatomic, strong) IBOutlet NSTextField *topMarginTextField;
@property (nonatomic, strong) IBOutlet NSBox *fakeSessionView;
@property (nonatomic, strong) IBOutlet iTermBadgeConfigurationBadgeView *badgeView;
@end

@implementation iTermBadgeConfigurationWindowController {
    NSMutableDictionary *_profileMutations;
    NSString *_fontName;
    BOOL _ignoreFrameChange;
    IBOutlet BFPCompositeView *_fontPicker;
}

- (instancetype)initWithProfile:(Profile *)profile {
    self = [self initWithWindowNibName:NSStringFromClass(self.class)];
    if (self) {
        _profile = [profile copy];
        _fontName = [iTermProfilePreferences stringForKey:KEY_BADGE_FONT inProfile:profile];
        _profileMutations = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)updateWindowFrame {
    const CGFloat maxWidth = MIN(0.95, _maxWidthTextField.doubleValue / 100.0);
    const CGFloat maxHeight = MIN(0.95, _maxHeightTextField.doubleValue / 100.0);
    const CGFloat rightMargin = _rightMarginTextField.doubleValue;
    const CGFloat topMargin = _topMarginTextField.doubleValue;

    NSRect frame = NSInsetRect(_fakeSessionView.frame, 6, 6);

    NSSize delta = NSZeroSize;
    CGFloat minimumWindowWidth = rightMargin / (1 - maxWidth);
    if (maxWidth < 1 && minimumWindowWidth > frame.size.width) {
        delta.width = minimumWindowWidth - frame.size.width;
    }

    CGFloat minimumWindowHeight = topMargin / (1 - maxHeight);
    if (maxHeight < 1 && minimumWindowHeight > frame.size.height) {
        delta.height = minimumWindowHeight - frame.size.height;
    }

    if (!NSEqualSizes(delta, NSZeroSize)) {
        NSRect windowFrame = self.window.frame;
        windowFrame.size.width += delta.width;
        windowFrame.size.height += delta.height;
        [self.window setFrame:windowFrame display:YES animate:NO];
    }
}

- (void)windowDidLoad {
    [super windowDidLoad];
    const CGFloat rightMargin = [iTermProfilePreferences doubleForKey:KEY_BADGE_RIGHT_MARGIN inProfile:_profile];
    const CGFloat topMargin = [iTermProfilePreferences doubleForKey:KEY_BADGE_TOP_MARGIN inProfile:_profile];
    const CGFloat maxWidth = [iTermProfilePreferences doubleForKey:KEY_BADGE_MAX_WIDTH inProfile:_profile];
    const CGFloat maxHeight = [iTermProfilePreferences doubleForKey:KEY_BADGE_MAX_HEIGHT inProfile:_profile];

    _fontPicker.font = self.font;
    _fontPicker.delegate = self;
    [_fontPicker removeSizePicker];
    [_fontPicker removeMemberPicker];
    _maxWidthTextField.doubleValue = MIN(0.95, maxWidth) * 100.0;
    _maxHeightTextField.doubleValue = MIN(0.95, maxHeight) * 100.0;
    _rightMarginTextField.doubleValue = MAX(0, rightMargin);
    _topMarginTextField.doubleValue = MAX(0, topMargin);

    _badgeView.delegate = self;
    _ignoreFrameChange = YES;
    [self setBadgeFrameFromTextFields];
    _ignoreFrameChange = NO;
    _fakeSessionView.fillColor = [[iTermProfilePreferences objectForKey:KEY_BACKGROUND_COLOR inProfile:_profile] colorValue];
}

- (NSFont *)font {
    NSFont *font;
    if (_fontName) {
        font = [NSFont fontWithName:_fontName size:12];
        if (font) {
            return font;
        }
    }

    font = [NSFont fontWithName:@"Helvetica" size:12];
    if (font) {
        return font;
    }

    return [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

- (Profile *)profileMutations {
    return @{ KEY_BADGE_MAX_WIDTH: @(MIN(0.95, _maxWidthTextField.doubleValue / 100.0)),
              KEY_BADGE_MAX_HEIGHT: @(MIN(0.95, _maxHeightTextField.doubleValue / 100.0)),
              KEY_BADGE_RIGHT_MARGIN: @(_rightMarginTextField.doubleValue),
              KEY_BADGE_TOP_MARGIN: @(_topMarginTextField.doubleValue),
              KEY_BADGE_FONT: _fontName ?: @"" };
}

- (void)setBadgeFrameFromTextFields {
    [self updateWindowFrame];

    const NSSize containerSize = self.badgeContainerSize;
    const CGFloat right = round(containerSize.width - _rightMarginTextField.integerValue);
    const CGFloat top = round(containerSize.height - _topMarginTextField.integerValue);
    const CGFloat height = round(MIN(95, _maxHeightTextField.integerValue / 100.0) * containerSize.height);
    const CGFloat width = round(MIN(95, _maxWidthTextField.integerValue / 100.0) * containerSize.width);
    NSRect insetFrame = NSMakeRect(right - width,
                                   top - height,
                                   width,
                                   height);
    _badgeView.frame = NSInsetRect(insetFrame, -iTermBadgeConfigurationBadgeViewInset, -iTermBadgeConfigurationBadgeViewInset);
}

- (NSSize)badgeContainerSize {
    return _badgeView.superview.frame.size;
}

- (IBAction)ok:(id)sender {
    _ok = YES;
    [self.window.sheetParent endSheet:self.window];
}

- (IBAction)cancel:(id)sender {
    [self.window.sheetParent endSheet:self.window];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
    _ignoreFrameChange = YES;
    [self setBadgeFrameFromTextFields];
    _ignoreFrameChange = NO;
}

#pragma mark - iTermBadgeConfigurationBadgeViewDelegate

- (void)badgeViewFrameDidChange:(NSRect)frameIncludingInsets {
    if (_ignoreFrameChange) {
        return;
    }
    NSRect frame = NSInsetRect(frameIncludingInsets, iTermBadgeConfigurationBadgeViewInset, iTermBadgeConfigurationBadgeViewInset);
    const NSSize containerSize = self.badgeContainerSize;
    _maxWidthTextField.integerValue = MIN(95, 100.0 * NSWidth(frame) / containerSize.width);
    _maxHeightTextField.integerValue = MIN(95, 100.0 * NSHeight(frame) / containerSize.height);
    _topMarginTextField.integerValue = MAX(0, containerSize.height - NSMaxY(frame));
    _rightMarginTextField.integerValue = MAX(0, containerSize.width - NSMaxX(frame));
}

- (Profile *)badgeViewProfile {
    return self.profile;
}

- (NSFont *)badgeViewFont {
    return [self font];
}

#pragma mark - BFPCompositeViewDelegate

- (void)fontPickerCompositeView:(BFPCompositeView * _Nonnull)view didSelectFont:(NSFont * _Nonnull)selectedFont {
    NSFont *font = selectedFont;
    if ([iTermAdvancedSettingsModel badgeFontIsBold]) {
        font = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSBoldFontMask];
    }
    _fontName = font.fontName;
    [_badgeView reload];
}

@end
