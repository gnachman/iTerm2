//
//  iTermIndicatorsHelper.h
//  iTerm2
//
//  Created by George Nachman on 11/23/14.
//
//

#import <Cocoa/Cocoa.h>

extern NSString *const kiTermIndicatorBell;
extern NSString *const kiTermIndicatorWrapToTop;
extern NSString *const kiTermIndicatorWrapToBottom;

extern NSString *const kiTermIndicatorMaximized;
extern NSString *const kItermIndicatorBroadcastInput;
extern NSString *const kiTermIndicatorCoprocess;
extern NSString *const kiTermIndicatorAlert;
extern NSString *const kiTermIndicatorAllOutputSuppressed;
extern NSString *const kiTermIndicatorZoomedIn;
extern NSString *const kiTermIndicatorCopyMode;
extern NSString *const kiTermIndicatorDebugLogging;
extern NSString *const kiTermIndicatorFilter;
extern NSString *const kiTermIndicatorSecureKeyboardEntry_Forced;
extern NSString *const kiTermIndicatorSecureKeyboardEntry_User;
extern NSString *const kiTermIndicatorPinned;
extern NSString *const kiTermIndicatorAIChatLinked;
extern NSString *const kiTermIndicatorAIChatStreaming;
extern NSString *const kiTermIndicatorChannel;

extern CGFloat kiTermIndicatorStandardHeight;

@protocol iTermIndicatorsHelperDelegate <NSObject>

- (void)indicatorNeedsDisplay;
- (NSColor *)indicatorFullScreenFlashColor;

@end

@interface iTermIndicatorsHelper : NSObject

@property(nonatomic, assign) id<iTermIndicatorsHelperDelegate> delegate;
@property(nonatomic, readonly) NSInteger numberOfVisibleIndicators;
@property(nonatomic, assign) BOOL backgroundlessMode;
@property(nonatomic, assign) CGFloat indicatorSize; // Size for non-large indicators (default: 26)

// Alpha value for fullscreen flash.
@property(nonatomic, readonly) CGFloat fullScreenAlpha;
@property(nonatomic, copy) void (^configurationObserver)(void);

- (void)setIndicator:(NSString *)identifier visible:(BOOL)visible darkBackground:(BOOL)darkBackground;
- (void)beginFlashingIndicator:(NSString *)identifier darkBackground:(BOOL)darkBackground;
- (void)beginFlashingFullScreen;

// Use this from drawRect:
- (void)drawInFrame:(NSRect)frame;

// Use this with Metal
- (void)didDraw;

- (void)enumerateTopRightIndicatorsInFrame:(NSRect)frame andDraw:(BOOL)shouldDraw block:(void (^)(NSString *, NSImage *, NSRect, BOOL))block;
- (void)enumerateCenterIndicatorsInFrame:(NSRect)frame block:(void (^)(NSString *, NSImage *, NSRect, CGFloat, BOOL))block;

- (NSString *)helpTextForIndicatorAt:(NSPoint)point sessionID:(NSString *)sessionID;
- (NSString *)helpTextForIndicatorWithName:(NSString *)name sessionID:(NSString *)sessionID;
+ (NSArray<NSString *> *)sequentialIndicatorIdentifiers;
- (void)configurationDidComplete;

@end
