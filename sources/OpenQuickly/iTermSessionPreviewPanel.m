//
//  iTermSessionPreviewPanel.m
//  iTerm2
//

#import "iTermSessionPreviewPanel.h"

#import "PTYSession.h"

// Width of the preview side panel when shown.
static const CGFloat kSessionPreviewWidth = 400;
// Inset around the preview snapshot inside its container.
static const CGFloat kSessionPreviewInset = 12;
// Layout metrics for the labels block above the preview image. Shared between
// previewWindowFrameForParentFrame: (which sizes the window) and
// layoutPreviewContent (which places the subviews) so they can't drift.
static const CGFloat kSessionPreviewTitleHeight = 18;
static const CGFloat kSessionPreviewDetailHeight = 14;
static const CGFloat kSessionPreviewLabelGap = 2;
static const CGFloat kSessionPreviewGapBelowLabels = 8;

static CGFloat iTermSessionPreviewLabelsBlockHeight(void) {
    return kSessionPreviewTitleHeight + kSessionPreviewLabelGap +
           kSessionPreviewDetailHeight + kSessionPreviewGapBelowLabels;
}

// Flipped NSView so the preview container can lay out subviews from the top.
@interface iTermSessionPreviewContentView : NSView
@end

@implementation iTermSessionPreviewContentView
- (BOOL)isFlipped { return YES; }
@end

@implementation iTermSessionPreviewPanel {
    NSPanel *_window;
    NSImageView *_imageView;
    NSTextField *_titleLabel;
    NSTextField *_detailLabel;
    BOOL _attached;
    // The session most recently snapshotted, so we don't re-render the grid on
    // every update when the same session stays selected.
    NSString *_cachedSessionGuid;
    __weak NSWindow *_parentWindow;
}

- (void)buildWindowIfNeeded {
    if (_window) {
        return;
    }
    NSRect frame = NSMakeRect(0, 0, kSessionPreviewWidth, 400);
    _window = [[NSPanel alloc] initWithContentRect:frame
                                         styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                           backing:NSBackingStoreBuffered
                                             defer:YES];
    _window.opaque = NO;
    _window.backgroundColor = [NSColor clearColor];
    _window.hasShadow = YES;
    _window.releasedWhenClosed = NO;
    _window.hidesOnDeactivate = YES;
    _window.movableByWindowBackground = NO;
    _window.becomesKeyOnlyIfNeeded = YES;

    iTermSessionPreviewContentView *contentView = [[iTermSessionPreviewContentView alloc] initWithFrame:frame];
    contentView.wantsLayer = YES;
    contentView.layer.cornerRadius = 10;
    contentView.layer.masksToBounds = YES;
    _window.contentView = contentView;

    NSVisualEffectView *visual = [[NSVisualEffectView alloc] initWithFrame:contentView.bounds];
    visual.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    if (@available(macOS 10.16, *)) {
        visual.material = NSVisualEffectMaterialMenu;
    } else {
        visual.material = NSVisualEffectMaterialSheet;
    }
    visual.state = NSVisualEffectStateActive;
    visual.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:visual];

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = YES;
    _titleLabel.font = [NSFont boldSystemFontOfSize:13];
    _titleLabel.textColor = [NSColor labelColor];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.backgroundColor = [NSColor clearColor];
    _titleLabel.drawsBackground = NO;
    [contentView addSubview:_titleLabel];

    _detailLabel = [NSTextField labelWithString:@""];
    _detailLabel.translatesAutoresizingMaskIntoConstraints = YES;
    _detailLabel.font = [NSFont systemFontOfSize:11];
    _detailLabel.textColor = [NSColor secondaryLabelColor];
    _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _detailLabel.backgroundColor = [NSColor clearColor];
    _detailLabel.drawsBackground = NO;
    [contentView addSubview:_detailLabel];

    _imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    // Align top so the image sits flush with the labels above and any vertical
    // slack lands at the bottom of the preview.
    _imageView.imageAlignment = NSImageAlignTop;
    _imageView.wantsLayer = YES;
    _imageView.layer.cornerRadius = 4;
    _imageView.layer.masksToBounds = YES;
    _imageView.layer.borderColor = [[NSColor separatorColor] CGColor];
    _imageView.layer.borderWidth = 0.5;
    [contentView addSubview:_imageView];
}

- (void)showForSession:(PTYSession *)session
                 title:(NSString *)title
                detail:(NSString *)detail
           parentFrame:(NSRect)parentFrame
          parentWindow:(NSWindow *)parentWindow {
    [self buildWindowIfNeeded];
    _parentWindow = parentWindow;

    if (![session.guid isEqualToString:_cachedSessionGuid]) {
        // Re-render only when the highlighted session actually changes; the
        // grid render is non-trivial and callers fire on every keystroke.
        // Only cache the guid on a successful render so a transient nil
        // (e.g. textview not yet laid out) doesn't lock in a blank preview.
        NSImage *image = [session terminalContentSnapshot];
        _imageView.image = image;
        _cachedSessionGuid = image ? [session.guid copy] : nil;
    }
    _titleLabel.stringValue = title ?: @"";
    _detailLabel.stringValue = detail ?: @"";

    BOOL wasVisible = _visible;
    _visible = YES;
    [self attachIfNeeded];
    [self repositionForParentFrame:parentFrame];
    if (!wasVisible) {
        [_window orderFront:nil];
    }
}

- (void)attachIfNeeded {
    if (_attached || _window == nil || _parentWindow == nil) {
        return;
    }
    [_parentWindow addChildWindow:_window ordered:NSWindowAbove];
    _attached = YES;
}

- (NSRect)windowFrameForParentFrame:(NSRect)parentFrame {
    const CGFloat gap = 8;
    const CGFloat inset = kSessionPreviewInset;
    const CGFloat labelsBlockHeight = iTermSessionPreviewLabelsBlockHeight();
    const CGFloat innerWidth = kSessionPreviewWidth - 2 * inset;

    // Size the image area to the snapshot's aspect ratio so a tall session
    // gets a tall preview and a short session gets a short preview.
    CGFloat imageHeight = 240;
    NSImage *image = _imageView.image;
    if (image && image.size.width > 0) {
        imageHeight = innerWidth * (image.size.height / image.size.width);
    }
    CGFloat windowHeight = inset + labelsBlockHeight + imageHeight + inset;
    NSScreen *screen = _parentWindow.screen ?: [NSScreen mainScreen];
    const NSRect visibleFrame = screen.visibleFrame;
    const CGFloat maxHeight = MAX(visibleFrame.size.height - 24, 300);
    windowHeight = MIN(MAX(windowHeight, 200), maxHeight);

    // Prefer the right side of the parent; flip to the left if the right side
    // would extend off-screen, and clamp horizontally to the visible frame.
    CGFloat originX = NSMaxX(parentFrame) + gap;
    if (originX + kSessionPreviewWidth > NSMaxX(visibleFrame)) {
        const CGFloat leftOriginX = NSMinX(parentFrame) - gap - kSessionPreviewWidth;
        if (leftOriginX >= NSMinX(visibleFrame)) {
            originX = leftOriginX;
        } else {
            originX = NSMaxX(visibleFrame) - kSessionPreviewWidth;
        }
    }
    originX = MAX(originX, NSMinX(visibleFrame));

    CGFloat originY = NSMaxY(parentFrame) - windowHeight;
    originY = MIN(MAX(originY, NSMinY(visibleFrame)), NSMaxY(visibleFrame) - windowHeight);

    return NSMakeRect(originX, originY, kSessionPreviewWidth, windowHeight);
}

- (void)repositionForParentFrame:(NSRect)parentFrame {
    if (_window == nil) {
        return;
    }
    [_window setFrame:[self windowFrameForParentFrame:parentFrame] display:YES];
    [self layoutContent];
}

- (void)layoutContent {
    NSView *contentView = _window.contentView;
    if (contentView == nil) {
        return;
    }
    const CGFloat inset = kSessionPreviewInset;
    const CGFloat innerWidth = contentView.bounds.size.width - 2 * inset;
    _titleLabel.frame = NSMakeRect(inset, inset, innerWidth, kSessionPreviewTitleHeight);
    _detailLabel.frame = NSMakeRect(inset,
                                    inset + kSessionPreviewTitleHeight + kSessionPreviewLabelGap,
                                    innerWidth,
                                    kSessionPreviewDetailHeight);
    const CGFloat imageY = inset + iTermSessionPreviewLabelsBlockHeight();
    const CGFloat imageHeight = MAX(contentView.bounds.size.height - imageY - inset, 0);
    _imageView.frame = NSMakeRect(inset, imageY, innerWidth, imageHeight);
}

- (void)hide {
    if (_visible) {
        [_window orderOut:nil];
        _visible = NO;
    }
}

- (void)teardown {
    if (_attached) {
        [_parentWindow removeChildWindow:_window];
        _attached = NO;
    }
    // Destroy the panel and rebuild it on the next presentation. orderOut alone
    // has proven unreliable for borderless NSPanels here; stale window state
    // can leave ghost panels on screen across opens.
    [_window close];
    _window = nil;
    _imageView = nil;
    _titleLabel = nil;
    _detailLabel = nil;
    _visible = NO;
    _cachedSessionGuid = nil;
    _parentWindow = nil;
}

@end
