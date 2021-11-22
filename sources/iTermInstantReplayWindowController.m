//
//  iTermInstantReplayWindowController.m
//  iTerm
//
//  Created by George Nachman on 3/15/14.
//
//

#import "iTermInstantReplayWindowController.h"

#import "DebugLogging.h"

static const float kAlphaValue = 0.9;

typedef NS_ENUM(NSUInteger, iTermInstantReplayState) {
    iTermInstantReplayStateNormal,
    iTermInstantReplayStateSetStart,
    iTermInstantReplayStateSetEnd
};

@interface iTermInstantReplayEventsView : NSView
@property (nonatomic, readonly) NSMutableArray<NSNumber *> *fractions;
@property (nonatomic) CGFloat startFraction;
@property (nonatomic) CGFloat endFraction;
@end

@implementation iTermInstantReplayEventsView

- (void)awakeFromNib {
    _fractions = [[NSMutableArray alloc] init];
}

- (CGFloat)xFromFraction:(CGFloat)fraction width:(CGFloat)width {
    return round(fraction * (width - 1));
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);

    __block CGFloat lastX = -1;
    const CGFloat width = self.frame.size.width;
    const CGFloat height = self.frame.size.height;

    if (_endFraction > _startFraction) {
        CGFloat minX = [self xFromFraction:_startFraction width:width];
        CGFloat maxX = [self xFromFraction:_endFraction width:width];
        NSRect rect = NSMakeRect(minX, 0, maxX - minX, height);
        [[[NSColor redColor] colorWithAlphaComponent:0.5] set];
        NSRectFill(rect);
    }

    NSAppearanceName bestMatch = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameDarkAqua,
                                                                                                NSAppearanceNameVibrantDark,
                                                                                                NSAppearanceNameAqua,
                                                                                                NSAppearanceNameVibrantLight ]];
    if ([bestMatch isEqualToString:NSAppearanceNameDarkAqua] ||
        [bestMatch isEqualToString:NSAppearanceNameVibrantDark]) {
        [[[NSColor whiteColor] colorWithAlphaComponent:0.5] set];
    } else {
        [[[NSColor blackColor] colorWithAlphaComponent:0.5] set];
    }
    [_fractions enumerateObjectsUsingBlock:^(NSNumber * _Nonnull fractionNumber, NSUInteger idx, BOOL * _Nonnull stop) {
        const double fraction = fractionNumber.doubleValue;
        const CGFloat x = [self xFromFraction:fraction width:width];
        if (x < NSMinX(dirtyRect) || x > NSMaxX(dirtyRect)) {
            return;
        }
        if (x == lastX) {
            return;
        }
        lastX = x;
        NSRectFill(NSMakeRect(x, 0, 1, height));
    }];
}

@end

@implementation iTermInstantReplayPanel

- (BOOL)canBecomeKeyWindow {
    return NO;
}

@end

@implementation iTermInstantReplayView {
    NSTrackingArea *_trackingArea;
}

- (void)updateTrackingAreas {

    if ([self window]) {
        if (_trackingArea) {
            [self removeTrackingArea:_trackingArea];
        }
        _trackingArea = [[NSTrackingArea alloc] initWithRect:[self visibleRect]
                                                     options:NSTrackingMouseMoved |NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                                                       owner:self
                                                    userInfo:nil];
        [self addTrackingArea:_trackingArea];
    }
}

- (void)mouseEntered:(NSEvent *)theEvent {
    [[NSCursor arrowCursor] set];
    [self.window.animator setAlphaValue:1];
}

- (void)mouseExited:(NSEvent *)theEvent {
    [self.window.animator setAlphaValue:kAlphaValue];
}

@end

@implementation iTermInstantReplayWindowController {
    IBOutlet NSSlider *_slider;
    IBOutlet NSTextField *_currentTimeLabel;
    IBOutlet NSTextField *_earliestTimeLabel;
    IBOutlet NSTextField *_latestTimeLabel;
    IBOutlet NSButton *_firstButton;
    IBOutlet NSButton *_secondButton;
    IBOutlet iTermInstantReplayEventsView *_eventsView;
    iTermInstantReplayState _state;
    long long _start;
    double _span;
    long long _firstTimestamp;
}

- (instancetype)init {
    return [super initWithWindowNibName:@"InstantReplay"];
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    self.window.level = NSFloatingWindowLevel;
    self.window.alphaValue = kAlphaValue;
}

- (void)windowWillClose:(NSNotification *)notification {
    [_delegate replaceSyntheticActiveSessionWithLiveSessionIfNeeded];
}

- (void)setDelegate:(id<iTermInstantReplayDelegate>)delegate {
    _delegate = delegate;
    if (delegate && [self isWindowLoaded]) {
        [self updateEvents];
    }
}

- (void)awakeFromNib {
    if (_delegate) {
        [self updateEvents];
    }
}

- (void)updateEvents {
    assert(_eventsView);
    assert(_delegate);
    _firstTimestamp = [_delegate instantReplayFirstTimestamp];
    long long lastTimestamp = [_delegate instantReplayLastTimestamp];
    _span = lastTimestamp - _firstTimestamp;
    [_eventsView.fractions removeAllObjects];
    for (long long i = _firstTimestamp; i > 0 && i <= lastTimestamp; i = [_delegate instantReplayTimestampAfter:i]) {
        NSNumber *fraction = @((i - _firstTimestamp) / _span);
        [_eventsView.fractions addObject:fraction];
    }
    [_eventsView setNeedsDisplay:YES];
}

- (IBAction)sliderMoved:(id)sender {
    __typeof(self) me = self;
    [_delegate instantReplaySeekTo:[sender floatValue]];
    [me updateInstantReplayView];
}

- (void)keyDown:(NSEvent *)theEvent {
    NSString *characters = [theEvent characters];
    __typeof(self) me = self;
    if ([characters length]) {
        unichar code = [characters characterAtIndex:0];
        switch (code) {
            case NSLeftArrowFunctionKey:
                [_delegate instantReplayStep:-1];
                [me updateInstantReplayView];
                break;
            case NSRightArrowFunctionKey:
                [_delegate instantReplayStep:1];
                [me updateInstantReplayView];
                break;
            case 27:
                [_delegate replaceSyntheticActiveSessionWithLiveSessionIfNeeded];
                break;
        }
    }
}

- (IBAction)exportButton:(id)sender {
    switch (_state) {
        case iTermInstantReplayStateNormal:
            [self setState:iTermInstantReplayStateSetStart byCancelling:NO];
            break;
        case iTermInstantReplayStateSetStart:
            [self setState:iTermInstantReplayStateSetEnd byCancelling:NO];
            break;
        case iTermInstantReplayStateSetEnd:
            [self setState:iTermInstantReplayStateNormal byCancelling:NO];
    }
}

- (IBAction)cancelButton:(id)sender {
    [self setState:iTermInstantReplayStateNormal byCancelling:YES];
}

- (void)setState:(iTermInstantReplayState)destinationState byCancelling:(BOOL)cancel {
    if (_state == iTermInstantReplayStateSetStart &&
               destinationState == iTermInstantReplayStateSetEnd) {
        _start = [_delegate instantReplayCurrentTimestamp];
        _eventsView.startFraction = (_start - _firstTimestamp) / _span;
        _eventsView.endFraction = _eventsView.startFraction;
    } else if (destinationState == iTermInstantReplayStateNormal &&
               _state == iTermInstantReplayStateSetEnd &&
               !cancel) {
        long long end = [_delegate instantReplayCurrentTimestamp];
        if (end < _start) {
            DLog(@"Beep: end is before start");
            NSBeep();
            return;
        }
        [_delegate instantReplayExportFrom:_start to:end];
    }
    _state = destinationState;
    switch (_state) {
        case iTermInstantReplayStateNormal:
            _firstButton.title = @"Export…";
            _eventsView.startFraction = 0;
            _eventsView.endFraction = 0;
            [_eventsView setNeedsDisplay:YES];
            _secondButton.hidden = YES;
            break;
        case iTermInstantReplayStateSetStart:
            _firstButton.title = @"Set Start";
            _secondButton.title = @"Cancel";
            _secondButton.hidden = NO;
            break;
        case iTermInstantReplayStateSetEnd:
            _firstButton.title = @"Set End";
            _secondButton.title = @"Cancel";
            _secondButton.hidden = NO;
    }
}

#pragma mark - NSWindowController

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self updateInstantReplayView];
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize {
    static const CGFloat kMinWidth = 270;
    return NSMakeSize(MAX(kMinWidth, frameSize.width), self.window.frame.size.height);
}

- (void)windowDidResize:(NSNotification *)notification {
    [self updateInstantReplayView];
}

#pragma mark - Private

- (NSString*)stringForTimestamp:(long long)timestamp
{
    time_t startTime = timestamp / 1000000;
    time_t now = time(NULL);
    struct tm startTimeParts;
    struct tm nowParts;
    localtime_r(&startTime, &startTimeParts);
    localtime_r(&now, &nowParts);
    NSDateFormatter* fmt = [[NSDateFormatter alloc] init];
    [fmt setDateStyle:NSDateFormatterShortStyle];
    if (startTimeParts.tm_year != nowParts.tm_year ||
        startTimeParts.tm_yday != nowParts.tm_yday) {
        [fmt setDateStyle:NSDateFormatterShortStyle];
    } else {
        [fmt setDateStyle:NSDateFormatterNoStyle];
    }
    [fmt setTimeStyle:NSDateFormatterMediumStyle];
    NSDate* date = [NSDate dateWithTimeIntervalSince1970:startTime];
    NSString* result = [fmt stringFromDate:date];
    return result;
}

- (void)updateInstantReplayView {
    if (![self.window isVisible]) {
        return;
    }
    long long timestamp = [_delegate instantReplayCurrentTimestamp];
    long long firstTimestamp = [_delegate instantReplayFirstTimestamp];
    long long lastTimestamp = [_delegate instantReplayLastTimestamp];
    if (timestamp >= 0) {
        [_currentTimeLabel setStringValue:[self stringForTimestamp:timestamp]];
        [_currentTimeLabel sizeToFit];
        float range = ((float)(lastTimestamp - firstTimestamp)) / 1000000.0;
        if (range > 0) {
            float offset = ((float)(timestamp - firstTimestamp)) / 1000000.0;
            float frac = offset / range;
            [_slider setFloatValue:frac];
        }
    } else {
        // Live view
        [_slider setFloatValue:1.0];
        [_currentTimeLabel setStringValue:@"Live View"];
        [_currentTimeLabel sizeToFit];
    }
    [_earliestTimeLabel setStringValue:[self stringForTimestamp:firstTimestamp]];
    [_latestTimeLabel setStringValue:@"Now"];

    // Adjust the width of the "earliest time" label, and keep the margin between it and the
    // slider the same.
    NSRect labelFrame = _earliestTimeLabel.frame;
    CGFloat margin = _slider.frame.origin.x - labelFrame.origin.x - labelFrame.size.width;
    [_earliestTimeLabel sizeToFit];
    [_latestTimeLabel sizeToFit];
    labelFrame = _earliestTimeLabel.frame;
    CGFloat newXOrigin = labelFrame.origin.x + labelFrame.size.width + margin;
    _slider.frame = NSMakeRect(newXOrigin,
                               _slider.frame.origin.y,
                               _slider.frame.origin.x + _slider.frame.size.width - newXOrigin,
                               _slider.frame.size.height);
    NSRect frame = _eventsView.frame;
    frame.origin.x = newXOrigin + 5;
    frame.size.width = _slider.frame.size.width - 10;
    _eventsView.frame = frame;

    // Align the currentTime with the slider
    NSRect f = [_currentTimeLabel frame];
    NSRect sf = [_slider frame];
    float newX = [_slider floatValue] * sf.size.width + sf.origin.x - f.size.width / 2;
    if (newX + f.size.width > sf.origin.x + sf.size.width) {
        newX = sf.origin.x + sf.size.width - f.size.width;
    }
    if (newX < sf.origin.x) {
        newX = sf.origin.x;
    }
    [_currentTimeLabel setFrameOrigin:NSMakePoint(newX, f.origin.y)];

    [self.window.contentView setNeedsDisplay:YES];

    if (_state == iTermInstantReplayStateSetEnd) {
        _eventsView.endFraction = (timestamp - _firstTimestamp) / _span;
        [_eventsView setNeedsDisplay:YES];

    }
}

@end
