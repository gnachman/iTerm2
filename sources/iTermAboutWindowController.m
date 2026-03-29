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
#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

static NSString *iTermAboutWindowControllerWhatsNewURLString = @"iterm2://whats-new/";

static const CGFloat kSponsorImageHeight = 32.0;
static const CGFloat kSponsorPadding = 8.0;
static const CGFloat kSponsorSpacing = 16.0;
static const CGFloat kSponsorRowBottomY = 174.0;
static const CGFloat kSponsorRowMargin = 22.0;

@interface iTermAboutWindowContentView : NSVisualEffectView
@end

@interface iTermSponsorBoxView : NSView
@end

@implementation iTermSponsorBoxView
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    self.layer.cornerRadius = 8.0;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [NSColor separatorColor].CGColor;
    self.layer.backgroundColor = [NSColor colorWithWhite:0.5 alpha:0.04].CGColor;
}
@end

@interface iTermSponsor: NSObject
@property (nonatomic) NSTrackingArea *trackingArea;
@property (nonatomic) NSView *view;
@property (nonatomic, copy) NSString *url;

+ (instancetype)sponsorWithView:(NSView *)view container:(NSView *)container url:(NSString *)url;
@end

@implementation iTermSponsor
+ (instancetype)sponsorWithView:(NSView *)view container:(NSView *)container url:(NSString *)url {
    iTermSponsor *sponsor = [[iTermSponsor alloc] init];
    sponsor.view = view;
    sponsor.url = url;

    NSRect rectInContainer = [container convertRect:view.bounds fromView:view];
    sponsor.trackingArea = [[NSTrackingArea alloc] initWithRect:rectInContainer
                                                        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                                                          owner:container
                                                       userInfo:nil];
    [container addTrackingArea:sponsor.trackingArea];
    return sponsor;
}

- (void)updateTrackingAreaForContainer:(NSView *)container {
    [container removeTrackingArea:self.trackingArea];
    NSRect rectInContainer = [container convertRect:self.view.bounds fromView:self.view];
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:rectInContainer
                                                    options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                                                      owner:container
                                                   userInfo:nil];
    [container addTrackingArea:self.trackingArea];
}
@end

@implementation iTermAboutWindowContentView {
    IBOutlet NSScrollView *_bottomAlignedScrollView;
    IBOutlet NSTextView *_sponsorsHeading;

    IBOutlet NSView *_whitebox;
    IBOutlet NSTextField *_whiteboxText;
    IBOutlet NSView *_codeRabbit;
    IBOutlet NSView *_serpApi;

    NSArray<iTermSponsor *> *_sponsors;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    NSRect frame = _bottomAlignedScrollView.frame;
    [super resizeSubviewsWithOldSize:oldSize];
    CGFloat topMargin = oldSize.height - NSMaxY(frame);
    frame.origin.y = self.frame.size.height - topMargin - frame.size.height;
    _bottomAlignedScrollView.frame = frame;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    _sponsorsHeading.selectable = YES;
    _sponsorsHeading.editable = NO;
    [_sponsorsHeading.textStorage setAttributedString:[NSAttributedString attributedStringWithHTML:_sponsorsHeading.textStorage.string
                                                                                              font:_sponsorsHeading.font
                                                                                    paragraphStyle:paragraphStyle]];

    [_whitebox removeFromSuperview];
    [_codeRabbit removeFromSuperview];
    [_serpApi removeFromSuperview];

    _sponsors = [self buildUnifiedSponsorRow];
}

- (NSView *)makeSponsorBoxWithImageNamed:(NSString *)imageName {
    NSImage *image = [NSImage imageNamed:imageName];
    CGFloat aspect = (image && image.size.height > 0)
        ? (image.size.width / image.size.height) : 1.0;
    CGFloat imageWidth = ceil(kSponsorImageHeight * aspect);

    NSImageView *imageView = [NSImageView imageViewWithImage:image];
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    imageView.translatesAutoresizingMaskIntoConstraints = NO;

    iTermSponsorBoxView *box = [[iTermSponsorBoxView alloc] initWithFrame:NSZeroRect];
    box.wantsLayer = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:imageView];

    [NSLayoutConstraint activateConstraints:@[
        [imageView.widthAnchor constraintEqualToConstant:imageWidth],
        [imageView.heightAnchor constraintEqualToConstant:kSponsorImageHeight],
        [imageView.topAnchor constraintEqualToAnchor:box.topAnchor constant:kSponsorPadding],
        [imageView.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-kSponsorPadding],
        [imageView.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:kSponsorPadding],
        [imageView.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-kSponsorPadding],
    ]];

    return box;
}

- (NSArray<iTermSponsor *> *)buildUnifiedSponsorRow {
    NSArray<NSDictionary *> *sponsorData = @[
        @{ @"image": @"whitebox_logo", @"url": @"https://whitebox.so/?utm_source=iTerm2" },
        @{ @"image": @"coderabbitai",  @"url": @"https://coderabbit.ai/" },
        @{ @"image": @"SerpApi",       @"url": @"https://serpapi.com/?utm_source=iterm" },
    ];

    NSMutableArray<NSView *> *boxes = [NSMutableArray array];
    for (NSDictionary *data in sponsorData) {
        [boxes addObject:[self makeSponsorBoxWithImageNamed:data[@"image"]]];
    }

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.distribution = NSStackViewDistributionGravityAreas;
    stack.spacing = kSponsorSpacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSView *box in boxes) {
        [stack addView:box inGravity:NSStackViewGravityCenter];
    }

    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kSponsorRowMargin],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kSponsorRowMargin],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:kSponsorRowBottomY],
    ]];

    [self layoutSubtreeIfNeeded];

    NSMutableArray<iTermSponsor *> *sponsors = [NSMutableArray array];
    for (NSUInteger i = 0; i < sponsorData.count; i++) {
        iTermSponsor *sponsor = [iTermSponsor sponsorWithView:boxes[i]
                                                    container:self
                                                          url:sponsorData[i][@"url"]];
        [sponsors addObject:sponsor];
    }
    return [sponsors copy];
}


- (void)mouseEntered:(NSEvent *)theEvent {
    [NSCursor.pointingHandCursor set];
}

- (void)mouseExited:(NSEvent *)theEvent {
    [NSCursor.arrowCursor set];
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

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (iTermSponsor *sponsor in _sponsors) {
        [sponsor updateTrackingAreaForContainer:self];
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
        if ([versionNumber hasPrefix:@"3.6."] || [versionString isEqualToString:@"unknown"]) {
            whatsNew = [self attributedStringWithLinkToURL:iTermAboutWindowControllerWhatsNewURLString
                                                     title:@"What’s New in 3.6?\n"];
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
