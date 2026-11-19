@class NSClipView, NSView;
@protocol NSScrollViewDelegate;

@interface NSScrollView : NSView <NSGestureRecognizerDelegate> {
    NSClipView *_contentView;
    struct { unsigned char  : 5; unsigned char findBarPosition : 2; } _sFlags;
}

@property (class) Class rulerViewClass;
@property (class, readonly) Class _horizontalScrollerClass;
@property BOOL rulersVisible;
@property (readonly) struct NSEdgeInsets { double x0; double x1; double x2; double x3; } _distancesScrolledFromDocumentEdges;
@property (nonatomic, setter=_setContentExtendsUnderHeader:) BOOL _contentExtendsUnderHeader;
@property (getter=isFindBarVisible) BOOL findBarVisible;
@property (copy, nonatomic) id /* block */ scrollHandler;

+ (struct CGSize { double x0; double x1; })frameSizeForContentSize:(struct CGSize { double x0; double x1; })a0 hasHorizontalScroller:(BOOL)a1;
- (id)scrollerImpPair;
- (void)_drawRect:(struct CGRect { struct CGPoint { double x0; double x1; } x0; struct CGSize { double x0; double x1; } x1; })a0 clip:(BOOL)a1;
- (void)_performWithCompletion:(void (^ /* unknown block signature */)(id, BOOL))a0 queue:(id)a1;
- (void)_enumerate:(id /* block */)a0;
- (id)_nested:(id<NSCopying> (^)(NSDictionary<NSString *, NSArray<id> *> *))a0;
- (void)_anonymous:(id)a0 :(id)a1;
- (void)allowedPocketEdges;

@end
