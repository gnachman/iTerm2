//
//  iTermAboutWindowController.m
//  iTerm2
//
//  Created by George Nachman on 9/21/14.
//
//

#import "iTermAboutWindowController.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermController.h"
#import "iTermLaunchExperienceController.h"
#import "iTermPreferences.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "PreferencePanel.h"
#import "PTYWindow.h"
#import "PseudoTerminal.h"

static NSString *iTermAboutWindowControllerWhatsNewURLString = @"iterm2://whats-new/";

static const CGFloat kSponsorImageHeight = 32.0;
static const CGFloat kSponsorPadding = 8.0;
static const CGFloat kSponsorSpacing = 16.0;
// Y origin of the sponsor row, matching the original nib position.
static const CGFloat kSponsorRowY = 170.0;

@interface iTermAboutWindowContentView : NSVisualEffectView
- (void)configureForDark:(BOOL)dark;
@end

@interface iTermSponsorBoxView : NSView
@end

@implementation iTermSponsorBoxView
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    [super updateLayer];
    self.layer.cornerRadius = 8.0;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [NSColor separatorColor].CGColor;
    self.layer.backgroundColor = [NSColor it_dynamicColorForLightMode:[NSColor colorWithWhite:0.0 alpha:0.04]
                                                                    darkMode:[NSColor colorWithWhite:1.0 alpha:0.08]].CGColor;
}
- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
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
    NSView *_sponsorWrapper;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    NSRect frame = _bottomAlignedScrollView.frame;
    [super resizeSubviewsWithOldSize:oldSize];
    CGFloat topMargin = oldSize.height - NSMaxY(frame);
    frame.origin.y = self.frame.size.height - topMargin - frame.size.height;
    _bottomAlignedScrollView.frame = frame;
    [self updateSponsorWrapperLayout];
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.material = NSVisualEffectMaterialHUDWindow;
    self.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.state = NSVisualEffectStateActive;

    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    _sponsorsHeading.selectable = YES;
    _sponsorsHeading.editable = NO;
    [_sponsorsHeading.textStorage setAttributedString:[NSAttributedString attributedStringWithHTML:_sponsorsHeading.textStorage.string
                                                                                              font:_sponsorsHeading.font
                                                                                    paragraphStyle:paragraphStyle]];

    _sponsors = [self buildUnifiedSponsorRow];
}

- (void)updateSponsorWrapperLayout {
    if (!_sponsorWrapper || _sponsors.count == 0) {
        return;
    }
    // Derived from the sponsor row rather than named logo outlets, so the
    // wrapper keeps fitting when sponsors are added or removed.
    CGFloat sponsorLogoMinY = CGFLOAT_MAX;
    for (iTermSponsor *sponsor in _sponsors) {
        sponsorLogoMinY = MIN(sponsorLogoMinY, NSMinY(sponsor.view.frame));
    }
    CGFloat headingTop = NSMaxY(_sponsorsHeading.frame);
    if (sponsorLogoMinY == CGFLOAT_MAX || headingTop == 0) {
        return;
    }
    const CGFloat kWrapperInset = 16;
    const CGFloat kWrapperGap = 12;
    CGFloat wrapperY = sponsorLogoMinY - kWrapperGap;
    CGFloat wrapperHeight = (headingTop + kWrapperGap) - wrapperY;
    _sponsorWrapper.frame = NSMakeRect(kWrapperInset,
                                       wrapperY,
                                       self.frame.size.width - kWrapperInset * 2,
                                       wrapperHeight);
}

- (void)configureForDark:(BOOL)dark {
    _bottomAlignedScrollView.drawsBackground = NO;
    _bottomAlignedScrollView.contentView.drawsBackground = NO;
    _bottomAlignedScrollView.hasVerticalScroller = YES;
    _bottomAlignedScrollView.autohidesScrollers = YES;
    _bottomAlignedScrollView.wantsLayer = YES;
    _bottomAlignedScrollView.layer.cornerRadius = 10;
    _bottomAlignedScrollView.layer.masksToBounds = YES;
    _bottomAlignedScrollView.layer.backgroundColor = dark
        ? [NSColor colorWithWhite:0 alpha:0.18].CGColor
        : [NSColor colorWithWhite:1 alpha:0.22].CGColor;

    if (!_sponsorWrapper) {
        const CGFloat kWrapperInset = 16;
        _sponsorWrapper = [[NSView alloc] initWithFrame:NSMakeRect(kWrapperInset, 0,
                                                                    self.frame.size.width - kWrapperInset * 2,
                                                                    80)];
        _sponsorWrapper.wantsLayer = YES;
        _sponsorWrapper.layer.cornerRadius = 8;
        _sponsorWrapper.autoresizingMask = NSViewNotSizable;
        [self addSubview:_sponsorWrapper positioned:NSWindowBelow relativeTo:nil];
    }
    _sponsorWrapper.layer.backgroundColor = dark
        ? [NSColor colorWithWhite:1 alpha:0.07].CGColor
        : [NSColor colorWithWhite:0 alpha:0.05].CGColor;

    [self updateSponsorWrapperLayout];
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
        NSString *versionString = [NSString stringWithFormat: @"Build %@\n\n", versionNumber];
        NSAttributedString *whatsNew = nil;
        if ([versionNumber hasPrefix:@"3.7."] || [versionString isEqualToString:@"unknown"]) {
            whatsNew = [self attributedStringWithLinkToURL:iTermAboutWindowControllerWhatsNewURLString
                                                     title:@"What’s New in 3.7?\n"];
        }

        NSAttributedString *webAString = [self attributedStringWithLinkToURL:@"https://iterm2.com/"
                                                                       title:@"Home Page"];
        NSAttributedString *bugsAString =
                [self attributedStringWithLinkToURL:@"https://iterm2.com/bugs"
                                              title:@"Report a bug"];
        NSAttributedString *creditsAString =
                [self attributedStringWithLinkToURL:@"https://iterm2.com/credits"
                                              title:@"Credits"];

        // Force IBOutlets to be bound by creating window.
        [self window];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(themeDidChange:)
                                                     name:kRefreshTerminalNotification
                                                   object:nil];
        [self applyThemeAppearance];

        NSDictionary *versionAttributes = @{ NSForegroundColorAttributeName: [NSColor controlTextColor] };
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

- (void)themeDidChange:(NSNotification *)notification {
    [self applyThemeAppearance];
}

- (void)applyThemeAppearance {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    BOOL isDark = (preferredStyle == TAB_STYLE_DARK || preferredStyle == TAB_STYLE_DARK_HIGH_CONTRAST);
    if (preferredStyle == TAB_STYLE_MINIMAL) {
        PseudoTerminal *terminal = [[iTermController sharedInstance] currentTerminal];
        NSColor *bgColor = [terminal.ptyWindow it_terminalWindowDecorationBackgroundColor];
        isDark = bgColor.perceivedBrightness < 0.5;
    }

    self.window.backgroundColor = [NSColor clearColor];
    self.window.appearance = isDark ? [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark] : nil;

    [(iTermAboutWindowContentView *)self.window.contentView configureForDark:isDark];
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
    NSString *string = [NSString stringWithFormat:@"Loading supporters…"];
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
        [self setPatronsString:[[NSAttributedString alloc] initWithString:@"Error loading patrons :("
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
