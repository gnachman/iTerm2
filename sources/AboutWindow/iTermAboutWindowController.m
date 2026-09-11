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

static NSString *iTermAboutWindowControllerWhatsNewURLString = @"iterm2://whats-new/";

static const CGFloat kSponsorImageHeight = 32.0;
static const CGFloat kSponsorPadding = 8.0;
static const CGFloat kSponsorSpacing = 16.0;
// Y origin of the sponsor row, matching the original nib position.
static const CGFloat kSponsorRowY = 170.0;

// Corner radius shared by the sponsor cards and, on macOS 26, the credits
// well, so the two containers read as one system. Tahoe's window chrome is
// rounder than its predecessors', and the containers follow it.
static const CGFloat kContainerCornerRadiusTahoe = 12.0;
static const CGFloat kContainerCornerRadiusLegacy = 8.0;
// Keeps the backer names off the well's rounded corners.
static const NSSize kCreditsTextInset = { 16.0, 12.0 };

// Before macOS 26, dark themes get a frosted-glass treatment and light themes
// keep the stock window, so these only ever apply when the theme is dark.
// Translucent black behind the credits so small text stays legible over the
// blur. Dark enough to read as a step down from the glass, light enough that
// the desktop still shows faintly through it.
static const CGFloat kDarkCreditsScrimAlpha = 0.28;
static const CGFloat kDarkCreditsScrimCornerRadius = 10.0;

static CGFloat iTermAboutContainerCornerRadius(void) {
    if (@available(macOS 26, *)) {
        return kContainerCornerRadiusTahoe;
    }
    return kContainerCornerRadiusLegacy;
}

// One fill for every container in the window, so the sponsor cards and the
// credits well read as the same surface.
static NSColor *iTermAboutContainerFillColor(void) {
    return [NSColor it_dynamicColorForLightMode:[NSColor colorWithWhite:0.0 alpha:0.04]
                                       darkMode:[NSColor colorWithWhite:1.0 alpha:0.08]];
}

@interface iTermAboutWindowContentView : NSVisualEffectView
@end

// Layer properties on the views AppKit manages get reset on the next display
// pass, so anything that paints a container does it from updateLayer.
@interface iTermSponsorBoxView : NSView
@end

@implementation iTermSponsorBoxView
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    [super updateLayer];
    self.layer.cornerRadius = iTermAboutContainerCornerRadius();
    self.layer.backgroundColor = iTermAboutContainerFillColor().CGColor;
}
- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}
@end

// Sits behind the credits scroll view. On macOS 26 it is a container like the
// sponsor cards; before that it is the dark scrim over the frosted glass.
@interface iTermAboutCreditsWellView : NSView
@end

@implementation iTermAboutCreditsWellView
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    [super updateLayer];
    if (@available(macOS 26, *)) {
        self.layer.cornerRadius = iTermAboutContainerCornerRadius();
        self.layer.backgroundColor = iTermAboutContainerFillColor().CGColor;
    } else {
        self.layer.cornerRadius = kDarkCreditsScrimCornerRadius;
        self.layer.backgroundColor = [NSColor colorWithWhite:0 alpha:kDarkCreditsScrimAlpha].CGColor;
    }
}
@end

@interface iTermSponsor: NSObject
@property (nonatomic) NSView *view;
@property (nonatomic, copy) NSString *url;
@end

@implementation iTermSponsor
@end

@implementation iTermAboutWindowContentView {
    IBOutlet NSScrollView *_bottomAlignedScrollView;
    IBOutlet NSTextView *_sponsorsHeading;

    NSArray<iTermSponsor *> *_sponsors;
    iTermAboutCreditsWellView *_creditsWell;
    NSVisualEffectMaterial _stockMaterial;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    NSRect frame = _bottomAlignedScrollView.frame;
    [super resizeSubviewsWithOldSize:oldSize];
    CGFloat topMargin = oldSize.height - NSMaxY(frame);
    frame.origin.y = self.frame.size.height - topMargin - frame.size.height;
    _bottomAlignedScrollView.frame = frame;
    _creditsWell.frame = frame;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    _stockMaterial = self.material;

    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    _sponsorsHeading.selectable = YES;
    _sponsorsHeading.editable = NO;
    NSString *headingHTML = NSLocalizedStringWithDefaultValue(@"About.BackersHeading", nil, [NSBundle mainBundle], @"iTerm2 is supported by these backers on <a href=\"https://patreon.com/gnachman\">Patreon</a> and <a href=\"https://github.com/sponsors/gnachman\">GitHub Sponsors</a>", @"About window heading. Keep the <a href=...> HTML tags and the URLs. ‘Patreon’ and ‘GitHub Sponsors’ are brand names, keep them. Only translate the prose ‘iTerm2 is supported by these backers on’ and ‘and’.");
    [_sponsorsHeading.textStorage setAttributedString:[NSAttributedString attributedStringWithHTML:headingHTML
                                                                                              font:_sponsorsHeading.font
                                                                                    paragraphStyle:paragraphStyle]];

    _sponsors = [self buildUnifiedSponsorRow];

    _creditsWell = [[iTermAboutCreditsWellView alloc] initWithFrame:_bottomAlignedScrollView.frame];
    _creditsWell.autoresizingMask = _bottomAlignedScrollView.autoresizingMask;
    [self addSubview:_creditsWell positioned:NSWindowBelow relativeTo:_bottomAlignedScrollView];
    NSTextView *creditsTextView = [NSTextView castFrom:_bottomAlignedScrollView.documentView];
    creditsTextView.textContainerInset = kCreditsTextInset;

    [self applyAppearanceTreatment];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self applyAppearanceTreatment];
}

// On macOS 26 the About window is a plain window-background window, the way
// the system's own About panel is, with the credits in a container like the
// sponsor cards; the colours are dynamic, so light and dark share one path.
// Before macOS 26, dark themes get frosted glass with a scrim behind the
// credits and light themes keep the stock window.
- (void)applyAppearanceTreatment {
    if (@available(macOS 26, *)) {
        self.material = NSVisualEffectMaterialWindowBackground;
        _creditsWell.hidden = NO;
        return;
    }
    const BOOL dark = self.effectiveAppearance.it_isDark;
    self.material = dark ? NSVisualEffectMaterialUnderWindowBackground : _stockMaterial;
    _creditsWell.hidden = !dark;
}

- (NSView *)makeSponsorBoxWithImageNamed:(NSString *)imageName title:(NSString *)title {
    NSImage *image = [NSImage imageNamed:imageName];
    CGFloat aspect = (image && image.size.height > 0)
        ? (image.size.width / image.size.height) : 1.0;
    CGFloat imageWidth = ceil(kSponsorImageHeight * aspect);
    CGFloat boxHeight = kSponsorImageHeight + 2 * kSponsorPadding;

    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(kSponsorPadding, kSponsorPadding, imageWidth, kSponsorImageHeight)];
    imageView.image = image;
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;

    CGFloat boxWidth = imageWidth + 2 * kSponsorPadding;

    NSTextField *label = nil;
    if (title) {
        label = [NSTextField labelWithString:title];
        label.font = [NSFont systemFontOfSize:13];
        label.textColor = [NSColor linkColor];
        [label sizeToFit];
        CGFloat labelX = kSponsorPadding + imageWidth + kSponsorPadding;
        label.frame = NSMakeRect(labelX,
                                 round((boxHeight - label.frame.size.height) / 2.0),
                                 label.frame.size.width,
                                 label.frame.size.height);
        boxWidth = NSMaxX(label.frame) + kSponsorPadding;
    }

    iTermSponsorBoxView *box = [[iTermSponsorBoxView alloc] initWithFrame:NSMakeRect(0, 0, boxWidth, boxHeight)];
    box.wantsLayer = YES;
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

    NSMutableArray<NSView *> *boxes = [NSMutableArray array];
    for (NSDictionary *data in sponsorData) {
        [boxes addObject:[self makeSponsorBoxWithImageNamed:data[@"image"] title:data[@"title"]]];
    }

    // Compute total row width to center the boxes.
    CGFloat totalWidth = 0;
    for (NSView *box in boxes) {
        totalWidth += box.frame.size.width;
    }
    totalWidth += kSponsorSpacing * (boxes.count - 1);

    // Place each box with frame-based layout to match the rest of this window.
    CGFloat x = round((self.bounds.size.width - totalWidth) / 2.0);
    for (NSView *box in boxes) {
        box.frame = NSMakeRect(x, kSponsorRowY, box.frame.size.width, box.frame.size.height);
        // Flexible bottom + left + right: stays centered and pinned to top on resize.
        box.autoresizingMask = NSViewMinYMargin | NSViewMinXMargin | NSViewMaxXMargin;
        [self addSubview:box];
        x += box.frame.size.width + kSponsorSpacing;
    }

    NSMutableArray<iTermSponsor *> *sponsors = [NSMutableArray array];
    for (NSUInteger i = 0; i < sponsorData.count; i++) {
        iTermSponsor *sponsor = [[iTermSponsor alloc] init];
        sponsor.view = boxes[i];
        sponsor.url = sponsorData[i][@"url"];
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

@interface iTermAboutWindowController()<NSTextViewDelegate>
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
        NSString *versionString = [NSString stringWithFormat: NSLocalizedStringWithDefaultValue(@"AboutWindow.BuildVersion", nil, [NSBundle mainBundle], @"Build %@\n\n", @"Build version line in the about window; placeholder is the build number"), versionNumber];
        NSAttributedString *whatsNew = nil;
        if ([versionNumber hasPrefix:@"3.7."] || [versionString isEqualToString:@"unknown"]) {
            whatsNew = [self attributedStringWithLinkToURL:iTermAboutWindowControllerWhatsNewURLString
                                                     title:NSLocalizedStringWithDefaultValue(@"AboutWindow.WhatsNew", nil, [NSBundle mainBundle], @"What’s New in 3.7?\n", @"Link title in the about window that opens the whats-new page for version 3.7")];
        }

        NSAttributedString *webAString = [self attributedStringWithLinkToURL:@"https://iterm2.com/"
                                                                       title:NSLocalizedStringWithDefaultValue(@"AboutWindow.HomePage", nil, [NSBundle mainBundle], @"Home Page", @"Link title in the about window that opens the iTerm2 home page")];
        NSAttributedString *bugsAString =
                [self attributedStringWithLinkToURL:@"https://iterm2.com/bugs"
                                              title:NSLocalizedStringWithDefaultValue(@"AboutWindow.ReportBug", nil, [NSBundle mainBundle], @"Report a bug", @"Link title in the about window that opens the bug reporting page")];
        NSAttributedString *creditsAString =
                [self attributedStringWithLinkToURL:@"https://iterm2.com/credits"
                                              title:NSLocalizedStringWithDefaultValue(@"AboutWindow.Credits", nil, [NSBundle mainBundle], @"Credits", @"Link title in the about window that opens the credits page")];

        // Force IBOutlets to be bound by creating window.
        [self window];

        NSDictionary *versionAttributes = @{ NSForegroundColorAttributeName: [NSColor controlTextColor] };
        // Localization unneeded
        NSAttributedString *bullet = [[NSAttributedString alloc] initWithString:@" ∙ "
                                                                     attributes:versionAttributes];
        [_dynamicText setLinkTextAttributes:self.linkTextViewAttributes];
        [[_dynamicText textStorage] deleteCharactersInRange:NSMakeRange(0, [[_dynamicText textStorage] length])];
        [[_dynamicText textStorage] appendAttributedString:[[NSAttributedString alloc] initWithString:versionString
                                                                                            attributes:versionAttributes]];
        if (whatsNew) {
            [[_dynamicText textStorage] appendAttributedString:whatsNew];
        }
        [[_dynamicText textStorage] appendAttributedString:webAString];
        [[_dynamicText textStorage] appendAttributedString:bullet];
        [[_dynamicText textStorage] appendAttributedString:bugsAString];
        [[_dynamicText textStorage] appendAttributedString:bullet];
        [[_dynamicText textStorage] appendAttributedString:creditsAString];
        [_dynamicText setAlignment:NSTextAlignmentCenter
                             range:NSMakeRange(0, [[_dynamicText textStorage] length])];

        [self setPatronsString:[self defaultPatronsString] animate:NO];

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

- (NSDictionary *)linkTextViewAttributes {
    return @{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
              NSForegroundColorAttributeName: [NSColor linkColor],
              NSCursorAttributeName: [NSCursor pointingHandCursor] };
}

- (void)setPatronsString:(NSAttributedString *)patronsAttributedString animate:(BOOL)animate {
    NSSize minSize = _patronsTextView.minSize;
    minSize.height = 1;
    _patronsTextView.minSize = minSize;

    [_patronsTextView setLinkTextAttributes:self.linkTextViewAttributes];
    [[_patronsTextView textStorage] deleteCharactersInRange:NSMakeRange(0, [[_patronsTextView textStorage] length])];
    [[_patronsTextView textStorage] appendAttributedString:patronsAttributedString];
    [_patronsTextView setAlignment:NSTextAlignmentLeft
                         range:NSMakeRange(0, [[_patronsTextView textStorage] length])];
    _patronsTextView.horizontallyResizable = NO;

    NSRect rect = _patronsTextView.enclosingScrollView.frame;
    [_patronsTextView sizeToFit];
    const CGFloat desiredHeight = [_patronsTextView.textStorage heightForWidth:rect.size.width];
    CGFloat diff = desiredHeight - rect.size.height;
    rect.size.height = desiredHeight;
    rect.origin.y -= diff;
    _patronsTextView.enclosingScrollView.frame = rect;
    
    rect = self.window.frame;
    rect.size.height += diff;
    rect.origin.y -= diff;
    [self.window setFrame:rect display:YES animate:animate];
}

- (NSAttributedString *)defaultPatronsString {
    NSString *string = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"AboutWindow.LoadingSupporters", nil, [NSBundle mainBundle], @"Loading supporters…", @"Placeholder text shown in the about window while the patron list loads")];
    NSMutableAttributedString *attributedString =
        [[NSMutableAttributedString alloc] initWithString:string
                                               attributes:self.attributes];
    return attributedString;
}

- (NSDictionary *)attributes {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    [style setMinimumLineHeight:18];
    [style setMaximumLineHeight:18];
    [style setLineSpacing:3];
    return @{ NSForegroundColorAttributeName: [NSColor controlTextColor],
              NSParagraphStyleAttributeName: style
    };
}

- (void)setPatrons:(NSArray *)patronNames {
    if (!patronNames.count) {
        [self setPatronsString:[[NSAttributedString alloc] initWithString:NSLocalizedStringWithDefaultValue(@"AboutWindow.ErrorLoadingPatrons", nil, [NSBundle mainBundle], @"Error loading patrons :(", @"Text shown in the about window when the patron list failed to load")
                                                                attributes:[self attributes]]
                       animate:NO];
        return;
    }

    NSArray *sortedNames = [patronNames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSString *string = [sortedNames componentsJoinedWithOxfordComma];
    NSDictionary *attributes = [self attributes];
    NSMutableAttributedString *attributedString =
        [[NSMutableAttributedString alloc] initWithString:string
                                               attributes:attributes];
    // Localization unneeded
    NSAttributedString *period = [[NSAttributedString alloc] initWithString:@"."];
    [attributedString appendAttributedString:period];

    [self setPatronsString:attributedString animate:YES];
}

- (NSAttributedString *)attributedStringWithLinkToURL:(NSString *)urlString title:(NSString *)title {
    NSDictionary *linkAttributes = @{ NSLinkAttributeName: [NSURL URLWithString:urlString] };
    NSString *localizedTitle = title;
    return [[NSAttributedString alloc] initWithString:localizedTitle
                                            attributes:linkAttributes];
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
