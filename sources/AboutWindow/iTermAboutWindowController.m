//
//  iTermAboutWindowController.m
//  iTerm2
//
//  Created by George Nachman on 9/21/14.
//
//

#import "iTermAboutWindowController.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermLaunchExperienceController.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "SFSymbolEnum/SFSymbolEnum.h"

static NSString *iTermAboutWindowControllerWhatsNewURLString = @"iterm2://whats-new/";
static NSString *const iTermAboutWindowHomePageURLString = @"https://iterm2.com/";
static NSString *const iTermAboutWindowReportBugURLString = @"https://iterm2.com/bugs";
static NSString *const iTermAboutWindowCreditsURLString = @"https://iterm2.com/credits";

// The window is one centred column, read top to bottom like a credits roll:
// who made it, who sponsors it, who backs it, and how to join them. Every
// vertical measure below is on an 8pt scale except where type sets it.
static const CGFloat kAboutSideMargin = 24.0;
static const CGFloat kAboutTopMargin = 28.0;
static const CGFloat kAboutBottomMargin = 24.0;
static const CGFloat kAboutIconSize = 96.0;
static const CGFloat kAboutIconToTitleGap = 12.0;
static const CGFloat kAboutTitleToBylineGap = 4.0;
static const CGFloat kAboutBylineToVersionGap = 4.0;
static const CGFloat kAboutVersionToButtonsGap = 16.0;
static const CGFloat kAboutButtonSpacing = 8.0;
static const CGFloat kAboutSectionGap = 28.0;
static const CGFloat kAboutSectionGapTight = 24.0;
static const CGFloat kAboutEyebrowToContentGap = 8.0;
static const CGFloat kAboutWellToFooterGap = 20.0;

static const CGFloat kAboutTitleFontSize = 22.0;
static const CGFloat kAboutBylineFontSize = 13.0;
static const CGFloat kAboutVersionFontSize = 12.0;
static const CGFloat kAboutEyebrowFontSize = 11.0;
static const CGFloat kAboutEyebrowTracking = 0.08;
static const CGFloat kAboutFooterFontSize = 12.0;
// Single-line text views for the build line and the footer.
static const CGFloat kAboutVersionLineHeight = 18.0;
static const CGFloat kAboutFooterLineHeight = 20.0;

static const CGFloat kSponsorImageHeight = 32.0;
static const CGFloat kSponsorPaddingVertical = 12.0;
static const CGFloat kSponsorPaddingHorizontal = 16.0;
static const CGFloat kSponsorSpacing = 12.0;

static const CGFloat kBackersFontSize = 13.0;
// 1.6× the type size, so a wall of names reads as a list rather than a block.
static const CGFloat kBackersLineHeight = 21.0;
static const CGFloat kBackersTierSpacing = 12.0;
// The marker before each higher-tier backer: a little smaller than the type,
// nudged down so it sits on the baseline rather than floating above it.
static const CGFloat kBackersStarSize = 11.0;
static const CGFloat kBackersStarBaselineOffset = -1.0;
static const NSSize kBackersTextInset = { 20.0, 16.0 };
// Keeps the window on screen when the backer list is long; past this the well
// scrolls instead of the window growing.
static const CGFloat kAboutScreenMargin = 40.0;

// Corner radius shared by the sponsor cards and the backer well, so the two
// containers read as one system. Tahoe's window chrome is rounder than its
// predecessors', and the containers follow it.
static const CGFloat kContainerCornerRadiusTahoe = 12.0;
static const CGFloat kContainerCornerRadiusLegacy = 8.0;

// Before macOS 26, dark themes get a frosted-glass treatment and light themes
// keep the stock window, so this only ever applies when the theme is dark.
// Translucent black behind the backers so small text stays legible over the
// blur. Dark enough to read as a step down from the glass, light enough that
// the desktop still shows faintly through it.
static const CGFloat kDarkBackersScrimAlpha = 0.28;

static CGFloat iTermAboutContainerCornerRadius(void) {
    if (@available(macOS 26, *)) {
        return kContainerCornerRadiusTahoe;
    }
    return kContainerCornerRadiusLegacy;
}

// One fill for every container in the window, so the sponsor cards and the
// backer well read as the same surface.
static NSColor *iTermAboutContainerFillColor(void) {
    return [NSColor it_dynamicColorForLightMode:[NSColor colorWithWhite:0.0 alpha:0.04]
                                       darkMode:[NSColor colorWithWhite:1.0 alpha:0.08]];
}

// A logo with a flat colour baked into the image has all four corners opaque
// and the same colour. Returns that colour, or nil for a transparent logo or
// one whose corners disagree (a gradient, a photo), which is left on the
// neutral fill rather than guessed at.
static NSColor *iTermAboutBakedBackgroundColorOfImage(NSImage *image) {
    static const CGFloat kOpaqueAlpha = 0.98;
    static const CGFloat kChannelTolerance = 4.0 / 255.0;
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cgImage) {
        return nil;
    }
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    const NSInteger maxX = bitmap.pixelsWide - 1;
    const NSInteger maxY = bitmap.pixelsHigh - 1;
    if (maxX < 0 || maxY < 0) {
        return nil;
    }
    NSColor *reference = nil;
    for (NSValue *corner in @[ [NSValue valueWithPoint:NSMakePoint(0, 0)],
                               [NSValue valueWithPoint:NSMakePoint(maxX, 0)],
                               [NSValue valueWithPoint:NSMakePoint(0, maxY)],
                               [NSValue valueWithPoint:NSMakePoint(maxX, maxY)] ]) {
        NSColor *color = [[bitmap colorAtX:corner.pointValue.x y:corner.pointValue.y] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        if (!color || color.alphaComponent < kOpaqueAlpha) {
            return nil;
        }
        if (!reference) {
            reference = color;
            continue;
        }
        if (fabs(color.redComponent - reference.redComponent) > kChannelTolerance ||
            fabs(color.greenComponent - reference.greenComponent) > kChannelTolerance ||
            fabs(color.blueComponent - reference.blueComponent) > kChannelTolerance) {
            return nil;
        }
    }
    return reference;
}

// Layer properties on the views AppKit manages get reset on the next display
// pass, so anything that paints a container does it from updateLayer.
@interface iTermSponsorBoxView : NSView
// The logo's own background when it has one baked in, so the card becomes a
// tile of that colour and the image's edge disappears into it.
@property (nonatomic, strong) NSColor *bakedBackgroundColor;
@end

@implementation iTermSponsorBoxView
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    [super updateLayer];
    self.layer.cornerRadius = iTermAboutContainerCornerRadius();
    self.layer.backgroundColor = (self.bakedBackgroundColor ?: iTermAboutContainerFillColor()).CGColor;
    // A hairline keeps a tile readable as a card whatever colour it turned out
    // to be: a white tile on the light window, a dark one on the dark window.
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [NSColor it_dynamicColorForLightMode:[NSColor colorWithWhite:0.0 alpha:0.08]
                                                         darkMode:[NSColor colorWithWhite:1.0 alpha:0.10]].CGColor;
}
- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}
@end

// Sits behind the backers scroll view. On macOS 26 it is a container like the
// sponsor cards; before that it is the dark scrim over the frosted glass.
@interface iTermAboutBackersWellView : NSView
@end

@implementation iTermAboutBackersWellView
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    [super updateLayer];
    self.layer.cornerRadius = iTermAboutContainerCornerRadius();
    if (@available(macOS 26, *)) {
        self.layer.backgroundColor = iTermAboutContainerFillColor().CGColor;
    } else {
        self.layer.backgroundColor = [NSColor colorWithWhite:0 alpha:kDarkBackersScrimAlpha].CGColor;
    }
}
@end

@interface iTermSponsor: NSObject
@property (nonatomic) NSView *view;
@property (nonatomic, copy) NSString *url;
@end

@implementation iTermSponsor
@end

// Button actions travel up the responder chain to the window controller.
@interface iTermAboutWindowController (Actions)
- (IBAction)openHomePage:(id)sender;
- (IBAction)reportBug:(id)sender;
- (IBAction)openCredits:(id)sender;
@end

@interface iTermAboutWindowContentView : NSVisualEffectView
// Height the content wants for the given height of the backer text, before
// the screen cap is applied.
- (CGFloat)preferredHeightForBackersTextHeight:(CGFloat)textHeight;
- (void)setBackersCount:(NSInteger)count;
@end

@implementation iTermAboutWindowContentView {
    IBOutlet NSImageView *_iconView;
    IBOutlet NSTextField *_titleField;
    IBOutlet NSTextField *_bylineField;
    IBOutlet NSScrollView *_versionScrollView;
    IBOutlet NSScrollView *_bottomAlignedScrollView;
    IBOutlet NSScrollView *_footerScrollView;
    IBOutlet NSTextView *_sponsorsHeading;

    NSArray<iTermSponsor *> *_sponsors;
    NSArray<NSButton *> *_buttons;
    NSTextField *_sponsorsEyebrow;
    NSTextField *_backersEyebrow;
    iTermAboutBackersWellView *_backersWell;
    NSVisualEffectMaterial _stockMaterial;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    _stockMaterial = self.material;

    _titleField.font = [NSFont systemFontOfSize:kAboutTitleFontSize weight:NSFontWeightSemibold];
    _titleField.textColor = [NSColor labelColor];
    _bylineField.font = [NSFont systemFontOfSize:kAboutBylineFontSize];
    _bylineField.textColor = [NSColor secondaryLabelColor];

    _buttons = @[
        [self makeButtonWithTitle:NSLocalizedStringWithDefaultValue(@"AboutWindow.HomePage", nil, [NSBundle mainBundle], @"Home Page", @"Button title in the about window that opens the iTerm2 home page")
                           action:@selector(openHomePage:)],
        [self makeButtonWithTitle:NSLocalizedStringWithDefaultValue(@"AboutWindow.ReportBug", nil, [NSBundle mainBundle], @"Report a Bug", @"Button title in the about window that opens the bug reporting page")
                           action:@selector(reportBug:)],
        [self makeButtonWithTitle:NSLocalizedStringWithDefaultValue(@"AboutWindow.Credits", nil, [NSBundle mainBundle], @"Credits", @"Button title in the about window that opens the credits page")
                           action:@selector(openCredits:)],
    ];

    _sponsorsEyebrow = [self makeEyebrowWithText:NSLocalizedStringWithDefaultValue(@"AboutWindow.SponsorsHeading", nil, [NSBundle mainBundle], @"Sponsors", @"Small uppercase heading in the about window above the row of sponsor logos")];
    _backersEyebrow = [self makeEyebrowWithText:NSLocalizedStringWithDefaultValue(@"AboutWindow.BackersHeading", nil, [NSBundle mainBundle], @"Backers", @"Small uppercase heading in the about window above the list of individual backers")];

    _sponsors = [self buildUnifiedSponsorRow];

    _backersWell = [[iTermAboutBackersWellView alloc] initWithFrame:_bottomAlignedScrollView.frame];
    [self addSubview:_backersWell positioned:NSWindowBelow relativeTo:_bottomAlignedScrollView];
    NSTextView *backersTextView = [NSTextView castFrom:_bottomAlignedScrollView.documentView];
    backersTextView.textContainerInset = kBackersTextInset;
    _bottomAlignedScrollView.hasVerticalScroller = YES;
    _bottomAlignedScrollView.autohidesScrollers = YES;

    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    _sponsorsHeading.selectable = YES;
    _sponsorsHeading.editable = NO;
    NSString *footerHTML = NSLocalizedStringWithDefaultValue(@"About.SupportFooter", nil, [NSBundle mainBundle], @"Support iTerm2 on <a href=\"https://patreon.com/gnachman\">Patreon</a> or <a href=\"https://github.com/sponsors/gnachman\">GitHub Sponsors</a>", @"About window footer inviting the user to sponsor the project. Keep the <a href=...> HTML tags and the URLs. ‘Patreon’ and ‘GitHub Sponsors’ are brand names, keep them. Only translate the prose ‘Support iTerm2 on’ and ‘or’.");
    [_sponsorsHeading.textStorage setAttributedString:[NSAttributedString attributedStringWithHTML:footerHTML
                                                                                              font:[NSFont systemFontOfSize:kAboutFooterFontSize]
                                                                                    paragraphStyle:paragraphStyle]];
    [_sponsorsHeading.textStorage addAttribute:NSForegroundColorAttributeName
                                         value:[NSColor secondaryLabelColor]
                                         range:NSMakeRange(0, _sponsorsHeading.textStorage.length)];

    [self applyAppearanceTreatment];
    [self layoutContent];
}

- (NSButton *)makeButtonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:nil action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
    [button sizeToFit];
    [self addSubview:button];
    return button;
}

- (NSTextField *)makeEyebrowWithText:(NSString *)text {
    NSTextField *label = [NSTextField labelWithAttributedString:[self makeEyebrowAttributedString:text]];
    label.alignment = NSTextAlignmentCenter;
    [label sizeToFit];
    [self addSubview:label];
    return label;
}

- (void)setBackersCount:(NSInteger)count {
    NSString *text = NSLocalizedStringWithDefaultValue(@"AboutWindow.BackersHeading", nil, [NSBundle mainBundle], @"Backers", @"Small uppercase heading in the about window above the list of individual backers");
    NSMutableAttributedString *eyebrow = [[NSMutableAttributedString alloc] initWithAttributedString:[self makeEyebrowAttributedString:text]];
    if (count > 0) {
        // Localization unneeded
        NSString *countString = [NSString stringWithFormat:@"  %@", [NSNumberFormatter localizedStringFromNumber:@(count)
                                                                                                         numberStyle:NSNumberFormatterDecimalStyle]];
        [eyebrow appendAttributedString:[[NSAttributedString alloc] initWithString:countString
                                                                        attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:kAboutEyebrowFontSize],
                                                                                      NSForegroundColorAttributeName: [NSColor tertiaryLabelColor] }]];
    }
    _backersEyebrow.attributedStringValue = eyebrow;
    [_backersEyebrow sizeToFit];
    [self layoutContent];
}

- (NSAttributedString *)makeEyebrowAttributedString:(NSString *)text {
    NSFont *font = [NSFont systemFontOfSize:kAboutEyebrowFontSize weight:NSFontWeightSemibold];
    return [[NSAttributedString alloc] initWithString:text.localizedUppercaseString
                                           attributes:@{ NSFontAttributeName: font,
                                                         NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
                                                         NSKernAttributeName: @(kAboutEyebrowFontSize * kAboutEyebrowTracking) }];
}

- (CGFloat)wellHeightForBackersTextHeight:(CGFloat)textHeight {
    return textHeight + kBackersTextInset.height * 2;
}

- (CGFloat)preferredHeightForBackersTextHeight:(CGFloat)textHeight {
    return (kAboutTopMargin +
            kAboutIconSize + kAboutIconToTitleGap +
            NSHeight(_titleField.frame) + kAboutTitleToBylineGap +
            NSHeight(_bylineField.frame) + kAboutBylineToVersionGap +
            kAboutVersionLineHeight + kAboutVersionToButtonsGap +
            NSHeight(_buttons.firstObject.frame) + kAboutSectionGap +
            NSHeight(_sponsorsEyebrow.frame) + kAboutEyebrowToContentGap +
            [self sponsorRowHeight] + kAboutSectionGapTight +
            NSHeight(_backersEyebrow.frame) + kAboutEyebrowToContentGap +
            [self wellHeightForBackersTextHeight:textHeight] + kAboutWellToFooterGap +
            kAboutFooterLineHeight +
            kAboutBottomMargin);
}

- (CGFloat)sponsorRowHeight {
    return kSponsorImageHeight + kSponsorPaddingVertical * 2;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutContent];
}

// Stacks everything from the top down. The backer well takes whatever height
// is left once the fixed rows are placed, so a long list scrolls inside it
// rather than pushing the footer off the window.
- (void)layoutContent {
    const CGFloat width = NSWidth(self.bounds);
    const CGFloat contentWidth = width - kAboutSideMargin * 2;
    __block CGFloat y = NSHeight(self.bounds) - kAboutTopMargin;

    void (^place)(NSView *, CGFloat, CGFloat) = ^(NSView *view, CGFloat height, CGFloat gapBelow) {
        y -= height;
        view.frame = NSMakeRect(kAboutSideMargin, y, contentWidth, height);
        y -= gapBelow;
    };
    void (^placeCentered)(NSView *, CGFloat) = ^(NSView *view, CGFloat gapBelow) {
        const NSSize size = view.frame.size;
        y -= size.height;
        view.frame = NSMakeRect(round((width - size.width) / 2), y, size.width, size.height);
        y -= gapBelow;
    };

    _iconView.frame = NSMakeRect(round((width - kAboutIconSize) / 2), y - kAboutIconSize, kAboutIconSize, kAboutIconSize);
    y -= kAboutIconSize + kAboutIconToTitleGap;
    place(_titleField, NSHeight(_titleField.frame), kAboutTitleToBylineGap);
    place(_bylineField, NSHeight(_bylineField.frame), kAboutBylineToVersionGap);
    place(_versionScrollView, kAboutVersionLineHeight, kAboutVersionToButtonsGap);

    CGFloat buttonsWidth = -kAboutButtonSpacing;
    for (NSButton *button in _buttons) {
        buttonsWidth += NSWidth(button.frame) + kAboutButtonSpacing;
    }
    const CGFloat buttonHeight = NSHeight(_buttons.firstObject.frame);
    y -= buttonHeight;
    CGFloat x = round((width - buttonsWidth) / 2);
    for (NSButton *button in _buttons) {
        button.frame = NSMakeRect(x, y, NSWidth(button.frame), buttonHeight);
        x += NSWidth(button.frame) + kAboutButtonSpacing;
    }
    y -= kAboutSectionGap;

    placeCentered(_sponsorsEyebrow, kAboutEyebrowToContentGap);
    [self layoutSponsorRowAtY:y - [self sponsorRowHeight]];
    y -= [self sponsorRowHeight] + kAboutSectionGapTight;

    placeCentered(_backersEyebrow, kAboutEyebrowToContentGap);

    const CGFloat footerHeight = kAboutFooterLineHeight;
    const CGFloat wellBottom = kAboutBottomMargin + footerHeight + kAboutWellToFooterGap;
    const CGFloat wellHeight = MAX(0, y - wellBottom);
    y -= wellHeight;
    _bottomAlignedScrollView.frame = NSMakeRect(kAboutSideMargin, y, contentWidth, wellHeight);
    _backersWell.frame = _bottomAlignedScrollView.frame;
    y -= kAboutWellToFooterGap;

    place(_footerScrollView, footerHeight, 0);
}

- (void)layoutSponsorRowAtY:(CGFloat)rowY {
    CGFloat totalWidth = -kSponsorSpacing;
    for (iTermSponsor *sponsor in _sponsors) {
        totalWidth += NSWidth(sponsor.view.frame) + kSponsorSpacing;
    }
    CGFloat x = round((NSWidth(self.bounds) - totalWidth) / 2.0);
    for (iTermSponsor *sponsor in _sponsors) {
        NSRect frame = sponsor.view.frame;
        frame.origin = NSMakePoint(x, rowY);
        sponsor.view.frame = frame;
        x += NSWidth(frame) + kSponsorSpacing;
    }
}

// On macOS 26 the About window is a plain window-background window, the way
// the system's own About panel is, with the backers in a container like the
// sponsor cards; the colours are dynamic, so light and dark share one path.
// Before macOS 26, dark themes get frosted glass with a scrim behind the
// backers and light themes keep the stock window.
- (void)applyAppearanceTreatment {
    if (@available(macOS 26, *)) {
        self.material = NSVisualEffectMaterialWindowBackground;
        _backersWell.hidden = NO;
        return;
    }
    const BOOL dark = self.effectiveAppearance.it_isDark;
    self.material = dark ? NSVisualEffectMaterialUnderWindowBackground : _stockMaterial;
    _backersWell.hidden = !dark;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self applyAppearanceTreatment];
}

- (NSView *)makeSponsorBoxWithImageNamed:(NSString *)imageName title:(NSString *)title {
    NSImage *image = [NSImage imageNamed:imageName];
    CGFloat aspect = (image && image.size.height > 0)
        ? (image.size.width / image.size.height) : 1.0;
    CGFloat imageWidth = ceil(kSponsorImageHeight * aspect);
    CGFloat boxHeight = [self sponsorRowHeight];

    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(kSponsorPaddingHorizontal, kSponsorPaddingVertical, imageWidth, kSponsorImageHeight)];
    imageView.image = image;
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;

    CGFloat boxWidth = imageWidth + 2 * kSponsorPaddingHorizontal;

    NSTextField *label = nil;
    if (title) {
        label = [NSTextField labelWithString:title];
        label.font = [NSFont systemFontOfSize:13];
        label.textColor = [NSColor linkColor];
        [label sizeToFit];
        CGFloat labelX = kSponsorPaddingHorizontal + imageWidth + kSponsorPaddingVertical;
        label.frame = NSMakeRect(labelX,
                                 round((boxHeight - label.frame.size.height) / 2.0),
                                 label.frame.size.width,
                                 label.frame.size.height);
        boxWidth = NSMaxX(label.frame) + kSponsorPaddingHorizontal;
    }

    iTermSponsorBoxView *box = [[iTermSponsorBoxView alloc] initWithFrame:NSMakeRect(0, 0, boxWidth, boxHeight)];
    box.wantsLayer = YES;
    box.bakedBackgroundColor = iTermAboutBakedBackgroundColorOfImage(image);
    [box addSubview:imageView];
    if (label) {
        [box addSubview:label];
    }

    return box;
}

- (NSArray<iTermSponsor *> *)buildUnifiedSponsorRow {
    NSArray<NSDictionary *> *sponsorData = @[
        // Localization unneeded
        @{ @"image": @"whitebox_logo", @"title": @"Whitebox", @"url": @"https://whitebox.so/?utm_source=iTerm2" },
        @{ @"image": @"coderabbitai",  @"url": @"https://coderabbit.ai/" },
        @{ @"image": @"SerpApi",       @"url": @"https://serpapi.com/?utm_source=iterm" },
        @{ @"image": @"LIMSIQ",        @"url": @"https://limsiq.com/iterm2?utm_source=iterm2&utm_medium=sponsorship&utm_campaign=about_box" },
        @{ @"image": @"BairesDev",     @"url": @"https://www.bairesdev.com/sponsoring-open-source-projects/" },
    ];

    NSMutableArray<iTermSponsor *> *sponsors = [NSMutableArray array];
    for (NSDictionary *data in sponsorData) {
        iTermSponsor *sponsor = [[iTermSponsor alloc] init];
        sponsor.view = [self makeSponsorBoxWithImageNamed:data[@"image"] title:data[@"title"]];
        sponsor.url = data[@"url"];
        [self addSubview:sponsor.view];
        [sponsors addObject:sponsor];
    }
    return [sponsors copy];
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (theEvent.clickCount == 1) {
        for (iTermSponsor *sponsor in _sponsors) {
            NSPoint pt = [sponsor.view convertPoint:theEvent.locationInWindow fromView:nil];
            if (NSPointInRect(pt, sponsor.view.bounds)) {
                [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:sponsor.url]];
                break;
            }
        }
    }
}

@end

@implementation iTermAboutWindowController {
    IBOutlet NSTextView *_dynamicText;
    IBOutlet NSTextView *_patronsTextView;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super initWithWindowNibName:@"AboutWindow"];
    if (self) {
        NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];
        NSString *const versionNumber = myDict[(NSString *)kCFBundleVersionKey];
        NSString *versionString = [NSString stringWithFormat: NSLocalizedStringWithDefaultValue(@"AboutWindow.BuildVersion", nil, [NSBundle mainBundle], @"Build %@", @"Build version line in the about window; placeholder is the build number"), versionNumber];
        NSAttributedString *whatsNew = nil;
        if ([versionNumber hasPrefix:@"3.7."] || [versionString isEqualToString:@"unknown"]) {
            whatsNew = [self attributedStringWithLinkToURL:iTermAboutWindowControllerWhatsNewURLString
                                                     title:NSLocalizedStringWithDefaultValue(@"AboutWindow.WhatsNew", nil, [NSBundle mainBundle], @"What’s New in 3.7?", @"Link title in the about window that opens the whats-new page for version 3.7")];
        }

        // Force IBOutlets to be bound by creating window.
        [self window];

        NSDictionary *versionAttributes = @{ NSForegroundColorAttributeName: [NSColor tertiaryLabelColor],
                                             NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:kAboutVersionFontSize weight:NSFontWeightRegular] };
        [_dynamicText setLinkTextAttributes:self.linkTextViewAttributes];
        [[_dynamicText textStorage] deleteCharactersInRange:NSMakeRange(0, [[_dynamicText textStorage] length])];
        [[_dynamicText textStorage] appendAttributedString:[[NSAttributedString alloc] initWithString:versionString
                                                                                            attributes:versionAttributes]];
        if (whatsNew) {
            // Localization unneeded
            [[_dynamicText textStorage] appendAttributedString:[[NSAttributedString alloc] initWithString:@"  ·  "
                                                                                                attributes:versionAttributes]];
            [[_dynamicText textStorage] appendAttributedString:whatsNew];
        }
        [_dynamicText setAlignment:NSTextAlignmentCenter
                             range:NSMakeRange(0, [[_dynamicText textStorage] length])];

        [self setPatronsString:[self defaultPatronsString] count:0 animate:NO];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSURL *url = [NSURL URLWithString:@"https://iterm2.com/patrons.txt"];
            NSData *data = [NSData dataWithContentsOfURL:url];
            NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSArray<NSString *> *patronNames = string.length > 0 ? [string componentsSeparatedByString:@"\n"] : nil;
            patronNames = [patronNames filteredArrayUsingBlock:^BOOL(NSString *name) {
                return name.length > 0;
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setPatrons:patronNames];
            });
        });
    }
    return self;
}

- (iTermAboutWindowContentView *)aboutContentView {
    return [iTermAboutWindowContentView castFrom:self.window.contentView];
}

- (NSDictionary *)linkTextViewAttributes {
    return @{ NSForegroundColorAttributeName: [NSColor linkColor],
              NSCursorAttributeName: [NSCursor pointingHandCursor] };
}

// The window grows to fit the backer list, as it always has, but never past
// the screen: beyond that the list scrolls inside its well instead.
- (void)setPatronsString:(NSAttributedString *)patronsAttributedString count:(NSInteger)count animate:(BOOL)animate {
    NSSize minSize = _patronsTextView.minSize;
    minSize.height = 1;
    _patronsTextView.minSize = minSize;
    [_patronsTextView setLinkTextAttributes:self.linkTextViewAttributes];
    [[_patronsTextView textStorage] deleteCharactersInRange:NSMakeRange(0, [[_patronsTextView textStorage] length])];
    [[_patronsTextView textStorage] appendAttributedString:patronsAttributedString];
    _patronsTextView.horizontallyResizable = NO;
    [_patronsTextView sizeToFit];

    const CGFloat textWidth = NSWidth(_patronsTextView.enclosingScrollView.frame) - kBackersTextInset.width * 2;
    const CGFloat textHeight = [_patronsTextView.textStorage heightForWidth:textWidth];
    iTermAboutWindowContentView *contentView = self.aboutContentView;
    [contentView setBackersCount:count];

    const CGFloat preferredHeight = [contentView preferredHeightForBackersTextHeight:textHeight];
    NSScreen *screen = self.window.screen ?: [NSScreen mainScreen];
    const CGFloat maxContentHeight = NSHeight(screen.visibleFrame) - kAboutScreenMargin * 2;
    NSRect contentRect = [self.window contentRectForFrameRect:self.window.frame];
    const CGFloat diff = MIN(preferredHeight, maxContentHeight) - NSHeight(contentRect);
    NSRect rect = self.window.frame;
    rect.size.height += diff;
    rect.origin.y -= diff;
    [self.window setFrame:rect display:YES animate:animate];
}

- (NSAttributedString *)defaultPatronsString {
    NSString *string = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"AboutWindow.LoadingSupporters", nil, [NSBundle mainBundle], @"Loading supporters…", @"Placeholder text shown in the about window while the patron list loads")];
    return [[NSAttributedString alloc] initWithString:string
                                           attributes:[self backersAttributesWithWeight:NSFontWeightRegular
                                                                                  color:[NSColor secondaryLabelColor]
                                                                          spacingBefore:0]];
}

- (NSDictionary *)backersAttributesWithWeight:(NSFontWeight)weight color:(NSColor *)color spacingBefore:(CGFloat)spacingBefore {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    style.minimumLineHeight = kBackersLineHeight;
    style.maximumLineHeight = kBackersLineHeight;
    style.paragraphSpacingBefore = spacingBefore;
    return @{ NSForegroundColorAttributeName: color,
              NSFontAttributeName: [NSFont systemFontOfSize:kBackersFontSize weight:weight],
              NSParagraphStyleAttributeName: style };
}

// The feed marks higher-tier backers by wrapping the name in ⭐️. They come
// first, in a heavier weight; everyone else follows. Tier is carried by
// weight, colour and position rather than by the emoji, so it survives both
// colourblindness and a wall of a hundred names.
- (NSAttributedString *)backersStringForTier:(NSArray<NSString *> *)names
                                      weight:(NSFontWeight)weight
                                       color:(NSColor *)color
                               spacingBefore:(CGFloat)spacingBefore
                                      marker:(NSAttributedString *)marker {
    NSDictionary *attributes = [self backersAttributesWithWeight:weight color:color spacingBefore:spacingBefore];
    NSMutableDictionary *separatorAttributes = [attributes mutableCopy];
    separatorAttributes[NSForegroundColorAttributeName] = [NSColor tertiaryLabelColor];
    // Localization unneeded
    NSAttributedString *separator = [[NSAttributedString alloc] initWithString:@"  ·  " attributes:separatorAttributes];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSArray<NSString *> *sortedNames = [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [sortedNames enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, BOOL *stop) {
        // A name only ever wraps at a separator, never inside itself.
        NSString *unbreakableName = [name stringByReplacingOccurrencesOfString:@" " withString:@"\u00A0"];
        if (index > 0) {
            [result appendAttributedString:separator];
        }
        if (marker) {
            [result appendAttributedString:marker];
        }
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:unbreakableName attributes:attributes]];
    }];
    return result;
}

// A gold star ahead of each higher-tier backer, drawn as a symbol rather than
// the feed's emoji so it takes the type's size and sits on its baseline.
- (NSAttributedString *)higherTierMarkerWithAttributes:(NSDictionary *)attributes {
    NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithHierarchicalColor:[NSColor systemYellowColor]];
    NSImage *star = [[NSImage imageWithSystemSymbolName:SFSymbolGetString(SFSymbolStarFill)
                                accessibilityDescription:NSLocalizedStringWithDefaultValue(@"AboutWindow.HigherTierBackerMarker", nil, [NSBundle mainBundle], @"Higher-tier backer", @"Accessibility description for the star shown before higher-tier backers in the about window")]
                     imageWithSymbolConfiguration:config];
    star.size = NSMakeSize(kBackersStarSize, kBackersStarSize);
    NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
    attachment.image = star;
    attachment.bounds = NSMakeRect(0, kBackersStarBaselineOffset, kBackersStarSize, kBackersStarSize);
    NSMutableAttributedString *marker = [[NSMutableAttributedString alloc] initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
    // The attachment opens the paragraph, so it has to carry the paragraph
    // style or the whole tier falls back to left alignment.
    [marker addAttributes:attributes range:NSMakeRange(0, marker.length)];
    // Localization unneeded
    [marker appendAttributedString:[[NSAttributedString alloc] initWithString:@"\u00A0" attributes:attributes]];
    return marker;
}

- (void)setPatrons:(NSArray *)patronNames {
    if (!patronNames.count) {
        [self setPatronsString:[[NSAttributedString alloc] initWithString:NSLocalizedStringWithDefaultValue(@"AboutWindow.ErrorLoadingPatrons", nil, [NSBundle mainBundle], @"Error loading patrons :(", @"Text shown in the about window when the patron list failed to load")
                                                                attributes:[self backersAttributesWithWeight:NSFontWeightRegular
                                                                                                       color:[NSColor secondaryLabelColor]
                                                                                               spacingBefore:0]]
                         count:0
                       animate:NO];
        return;
    }

    NSCharacterSet *starCharacters = [NSCharacterSet characterSetWithCharactersInString:@"⭐️"];
    NSMutableCharacterSet *starAndWhitespace = [starCharacters mutableCopy];
    [starAndWhitespace formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray<NSString *> *higherTier = [NSMutableArray array];
    NSMutableArray<NSString *> *everyoneElse = [NSMutableArray array];
    for (NSString *rawName in patronNames) {
        NSString *name = [rawName stringByTrimmingCharactersInSet:starAndWhitespace];
        if (name.length == 0) {
            continue;
        }
        if ([rawName rangeOfCharacterFromSet:starCharacters].location != NSNotFound) {
            [higherTier addObject:name];
        } else {
            [everyoneElse addObject:name];
        }
    }

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] init];
    if (higherTier.count) {
        [attributedString appendAttributedString:[self backersStringForTier:higherTier
                                                                     weight:NSFontWeightMedium
                                                                      color:[NSColor labelColor]
                                                              spacingBefore:0
                                                                     marker:[self higherTierMarkerWithAttributes:[self backersAttributesWithWeight:NSFontWeightMedium color:[NSColor labelColor] spacingBefore:0]]]];
    }
    if (everyoneElse.count) {
        if (attributedString.length) {
            // Localization unneeded
            [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        }
        [attributedString appendAttributedString:[self backersStringForTier:everyoneElse
                                                                     weight:NSFontWeightRegular
                                                                      color:[NSColor secondaryLabelColor]
                                                              spacingBefore:attributedString.length ? kBackersTierSpacing : 0
                                                                     marker:nil]];
    }
    [self setPatronsString:attributedString
                     count:higherTier.count + everyoneElse.count
                   animate:YES];
}

- (NSAttributedString *)attributedStringWithLinkToURL:(NSString *)urlString title:(NSString *)title {
    NSDictionary *linkAttributes = @{ NSLinkAttributeName: [NSURL URLWithString:urlString] };
    NSString *localizedTitle = title;
    return [[NSAttributedString alloc] initWithString:localizedTitle
                                            attributes:linkAttributes];
}

#pragma mark - Actions

- (IBAction)openHomePage:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:iTermAboutWindowHomePageURLString]];
}

- (IBAction)reportBug:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:iTermAboutWindowReportBugURLString]];
}

- (IBAction)openCredits:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:iTermAboutWindowCreditsURLString]];
}

#pragma mark - NSTextViewDelegate

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex {
    NSURL *url = [NSURL castFrom:link];
    if ([url.absoluteString isEqualToString:iTermAboutWindowControllerWhatsNewURLString]) {
        [iTermLaunchExperienceController forceShowWhatsNew];
        return YES;
    }
    return NO;
}

@end
