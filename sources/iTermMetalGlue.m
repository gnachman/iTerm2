//
//  iTermMetalGlue.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/8/17.
//

#import "iTermMetalGlue.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBoxDrawingBezierCurveFactory.h"
#import "iTermCharacterSource.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermData.h"
#import "iTermImageInfo.h"
#import "iTermMarkRenderer.h"
#import "iTermMetalPerFrameState.h"
#import "iTermSelection.h"
#import "iTermSmartCursorColor.h"
#import "iTermTextDrawingHelper.h"
#import "iTermTextRendererTransientState.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSStringITerm.h"
#import "PTYFontInfo.h"
#import "PTYTextView.h"
#import "VT100Screen.h"
#import "VT100ScreenMark.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermMetalGlue()<iTermMetalPerFrameStateDelegate>
@end

@implementation iTermMetalGlue {
    NSMutableSet<NSString *> *_missingImages;
    NSMutableSet<NSString *> *_loadedImages;
}

@synthesize oldCursorScreenCoord = _oldCursorScreenCoord;
@synthesize lastTimeCursorMoved = _lastTimeCursorMoved;

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(imageDidLoad:)
                                                     name:iTermImageDidLoad
                                                   object:nil];
        _missingImages = [NSMutableSet set];
        _loadedImages = [NSMutableSet set];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)imageDidLoad:(NSNotification *)notification {
    iTermImageInfo *image = notification.object;
    [_loadedImages addObject:image.uniqueIdentifier];
    if ([self missingImageIsVisible:image]) {
        [_textView setNeedsDisplay:YES];
    }
}

#pragma mark - Private

- (BOOL)missingImageIsVisible:(iTermImageInfo *)image {
    if (![_missingImages containsObject:image.uniqueIdentifier]) {
        return NO;
    }
    return [_textView imageIsVisible:image];
}

#pragma mark - iTermMetalDriverDataSource

- (BOOL)metalDriverShouldDrawFrame {
    return self.delegate.metalGlueContext != nil;
}

- (nullable id<iTermMetalDriverDataSourcePerFrameState>)metalDriverWillBeginDrawingFrame {
    if (self.textView.drawingHelper.delegate == nil) {
        return nil;
    }
    ITBetaAssert(self.delegate != nil, @"Nil delegate");
    ITBetaAssert(self.delegate.metalGlueContext != nil, @"Nil metal glue context");
    return [[iTermMetalPerFrameState alloc] initWithTextView:self.textView
                                                      screen:self.screen
                                                        glue:self
                                                     context:self.delegate.metalGlueContext];
}

- (void)metalDidFindImages:(NSSet<NSString *> *)foundImages
             missingImages:(NSSet<NSString *> *)missingImages
            animatedLines:(NSSet<NSNumber *> *)animatedLines {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_missingImages unionSet:missingImages];
        [self->_missingImages minusSet:foundImages];
        if (animatedLines.count) {
            self->_textView.drawingHelper.animated = YES;
        }
        int width = self->_textView.dataSource.width;
        long long offset = self->_textView.dataSource.totalScrollbackOverflow;
        for (NSNumber *absoluteLine in animatedLines) {
            long long abs = absoluteLine.longLongValue;
            if (abs >= offset) {
                int row = abs - offset;
                [self->_textView.dataSource setRangeOfCharsAnimated:NSMakeRange(0, width) onLine:row];
            }
        }
        NSMutableSet<NSString *> *newlyLoaded = [self->_missingImages mutableCopy];
        [newlyLoaded intersectSet:self->_loadedImages];
        if (newlyLoaded.count) {
            [self->_textView setNeedsDisplay:YES];
            [self->_missingImages minusSet:self->_loadedImages];
        }
    });
}

- (void)metalDriverDidDrawFrame:(id<iTermMetalDriverDataSourcePerFrameState>)perFrameState {
    // Don't invoke the callback if geometry has changed.
    iTermMetalPerFrameState *state = (iTermMetalPerFrameState *)perFrameState;
    if (!VT100GridSizeEquals(state.gridSize, VT100GridSizeMake(_textView.dataSource.width,
                                                               _textView.dataSource.height))) {
        return;
    }
    if (!CGSizeEqualToSize(state.cellSize,
                           CGSizeMake(_textView.charWidth, _textView.lineHeight))) {
        return;
    }
    if (state.scale != _textView.window.backingScaleFactor) {
        return;
    }
    [self.delegate metalGlueDidDrawFrameAndNeedsRedraw:state.isAnimating];
}

- (void)metalDriverDidProduceDebugInfo:(nonnull NSData *)archive {
    NSString *filename = @"/tmp/iTerm2-frame-capture.zip";
    [archive writeToFile:filename atomically:NO];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:filename] ]];
}

@end

NS_ASSUME_NONNULL_END
