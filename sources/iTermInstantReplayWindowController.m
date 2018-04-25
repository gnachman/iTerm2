//
//  iTermInstantReplayWindowController.m
//  iTerm
//
//  Created by George Nachman on 3/15/14.
//
//

#import "iTermInstantReplayWindowController.h"

static const float kAlphaValue = 0.9;

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
            [_trackingArea release];
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
    __weak IBOutlet NSSlider *_slider;
    __weak IBOutlet NSTextField *_currentTimeLabel;
    __weak IBOutlet NSTextField *_earliestTimeLabel;
    __weak IBOutlet NSTextField *_latestTimeLabel;
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

- (IBAction)sliderMoved:(id)sender {
    [self retain];
    [_delegate instantReplaySeekTo:[sender floatValue]];
    [self updateInstantReplayView];
    [self release];
}

- (void)keyDown:(NSEvent *)theEvent {
    NSString *characters = [theEvent characters];
    [self retain];  // In case delegate releases us
    if ([characters length]) {
        unichar code = [characters characterAtIndex:0];
        switch (code) {
            case NSLeftArrowFunctionKey:
                [_delegate instantReplayStep:-1];
                [self updateInstantReplayView];
                break;
            case NSRightArrowFunctionKey:
                [_delegate instantReplayStep:1];
                [self updateInstantReplayView];
                break;
            case 27:
                [_delegate replaceSyntheticActiveSessionWithLiveSessionIfNeeded];
                break;
        }
    }
    [self release];
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
    NSDateFormatter* fmt = [[[NSDateFormatter alloc] init] autorelease];
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
}

@end
