//
//  iTermMetalGlue.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/8/17.
//

#import "iTermMetalGlue.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAttributedStringBuilder.h"
#import "iTermBoxDrawingBezierCurveFactory.h"
#import "iTermCharacterSource.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermData.h"
#import "iTermImageInfo.h"
#import "iTermMarkRenderer.h"
#import "iTermConfigGenerationTracker.h"
#import "iTermMetalPerFrameState.h"
#import "iTermRowOutputCache.h"
#import "VT100LineInfo.h"
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
#import "PTYTextView+ARC.h"
#import "VT100Screen.h"
#import "VT100ScreenMark.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermMetalGlue()<iTermMetalPerFrameStateDelegate>
@end

@implementation iTermMetalGlue {
    NSMutableSet<NSString *> *_missingImages;
    NSMutableSet<NSString *> *_loadedImages;
    iTermAttributedStringBuilderStats _stats;
    iTermConfigGenerationTracker *_configGenerationTracker;
    // Persists across frames so unchanged rows can be reused. One per text view.
    iTermRowOutputCache *_rowOutputCache;
}

@synthesize oldCursorScreenCoord = _oldCursorScreenCoord;
@synthesize lastTimeCursorMoved = _lastTimeCursorMoved;

- (uint64_t)metalConfigGenerationForRenderInputs:(const iTermRowRenderInputs *)inputs
                                        colorMap:(nullable iTermColorMap *)colorMap
                                      colorSpace:(NSColorSpace *)colorSpace
                                       fontTable:(nullable iTermFontTable *)fontTable {
    return [_configGenerationTracker generationForRenderInputs:inputs
                                                      colorMap:colorMap
                                                    colorSpace:colorSpace
                                                     fontTable:fontTable];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(imageDidLoad:)
                                                     name:iTermImageDidLoad
                                                   object:nil];
        _missingImages = [NSMutableSet set];
        _loadedImages = [NSMutableSet set];
        _configGenerationTracker = [[iTermConfigGenerationTracker alloc] init];
        // Only visible rows are looked up in a frame; caching beyond the viewport
        // only speeds scrollback navigation, so a modest multiple of a tall
        // viewport is plenty. Each entry owns row-sized blobs (~20-25 KB on a wide
        // pane), so a larger cap would retain tens of MB per text view across split
        // panes and tabs for near-zero extra hit rate.
        _rowOutputCache = [[iTermRowOutputCache alloc] initWithCapacity:256];
        iTermPreciseTimerStatsInit(&_stats.attrsForChar, "Compute Attrs");
        iTermPreciseTimerStatsInit(&_stats.shouldSegment, "Segment");
        iTermPreciseTimerStatsInit(&_stats.buildMutableAttributedString, "Build attr strings");
        iTermPreciseTimerStatsInit(&_stats.combineAttributes, "Combine Attrs");
        iTermPreciseTimerStatsInit(&_stats.updateBuilder, "Update Builder");
        iTermPreciseTimerStatsInit(&_stats.advances, "Advances");
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)imageDidLoad:(NSNotification *)notification {
    id<iTermImageInfoReading> image = notification.object;
    [_loadedImages addObject:image.uniqueIdentifier];
    if ([self missingImageIsVisible:image]) {
        [_textView requestDelegateRedraw];
    }
}

#pragma mark - Private

- (BOOL)missingImageIsVisible:(id<iTermImageInfoReading>)image {
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
    if (!self.textView.drawingHelperIsValid) {
        return nil;
    }
    ITBetaAssert(self.delegate != nil, @"Nil delegate");
    ITBetaAssert(self.delegate.metalGlueContext != nil, @"Nil metal glue context");
    if ([iTermAdvancedSettingsModel metalRowOutputCacheEnabled]) {
        // The per-row cache keys grid rows on the per-line generation, which is not
        // advanced unless tracking is on (it is off by default so idle sessions
        // don't bump the shared counter on every dirty line). Turn it on now that a
        // cache-enabled frame is being built.
        VT100LineInfoEnableGenerationTracking();
    }
    iTermAttributedStringBuilderStatsPointers statsPointers = {
        .attrsForChar = &_stats.attrsForChar,
        .shouldSegment = &_stats.shouldSegment,
        .buildMutableAttributedString = &_stats.buildMutableAttributedString,
        .combineAttributes = &_stats.combineAttributes,
        .updateBuilder = &_stats.updateBuilder,
        .advances = &_stats.advances,
    };
    iTermAttributedStringBuilder *attributedStringBuilder = [[iTermAttributedStringBuilder alloc] initWithStats:statsPointers];
    return [[iTermMetalPerFrameState alloc] initWithTextView:self.textView
                                                      screen:self.screen
                                                        glue:self
                                                     context:self.delegate.metalGlueContext
                                         doubleWidthContext:self.delegate.metalGlueContextDoubleWidth
                                     attributedStringBuilder:attributedStringBuilder
                                              rowOutputCache:_rowOutputCache];
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
            [self->_textView requestDelegateRedraw];
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

- (iTermImageWrapper *)backgroundImage {
    return [self.delegate metalGlueBackgroundImage];
}

- (iTermBackgroundImageMode)backroundImageMode {
    return [self.delegate metalGlueBackgroundImageMode];
}

- (CGFloat)backgroundImageBlend {
    return [self.delegate metalGlueBackgroundImageBlend];
}

@end

NS_ASSUME_NONNULL_END
