//
//  iTermInstantReplayWindowController.m
//  iTerm
//
//  Created by George Nachman on 3/15/14.
//
//

#import "iTermInstantReplayWindowController.h"

@interface iTermInstantReplayWindowController ()

@end

@implementation iTermInstantReplayWindowController {
    IBOutlet NSSlider *_slider;
    IBOutlet NSTextField *_currentTimeLabel;
    IBOutlet NSTextField *_earliestTimeLabel;
    IBOutlet NSTextField *_latestTimeLabel;
}

- (id)init {
    return [super initWithWindowNibName:@"InstantReplay"];
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    self.window.level = NSFloatingWindowLevel;
    self.window.alphaValue = 0.7;
}

- (void)windowWillClose:(NSNotification *)notification {
    [_delegate instantReplayClose];
}

- (IBAction)sliderMoved:(id)sender {
    [self retain];
    [_delegate instantReplaySeekTo:[sender floatValue]];
    [self updateInstantReplayView];
    [self release];
}

- (IBAction)stepButtonPressed:(id)sender {
    [self retain];
    switch ([sender selectedSegment]) {
        case 0:
            [_delegate instantReplayStep:-1];
            break;
            
        case 1:
            [_delegate instantReplayStep:1];
            break;
            
    }
    [sender setSelected:NO forSegment:[sender selectedSegment]];
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
                [_delegate instantReplayClose];
                break;
        }
    }
    [self release];
}

#pragma mark - NSWindowController

- (void)windowDidBecomeKey:(NSNotification *)notification {
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
    [_earliestTimeLabel sizeToFit];
    [_latestTimeLabel setStringValue:@"Now"];
    
    // Align the currentTime with the slider
    NSRect f = [_currentTimeLabel frame];
    NSRect sf = [_slider frame];
    NSRect etf = [_earliestTimeLabel frame];
    float newSliderX = etf.origin.x + etf.size.width + 10;
    float dx = newSliderX - sf.origin.x;
    sf.origin.x = newSliderX;
    sf.size.width -= dx;
    [_slider setFrame:sf];
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
