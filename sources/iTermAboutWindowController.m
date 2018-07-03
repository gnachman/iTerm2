//
//  iTermAboutWindowController.m
//  iTerm2
//
//  Created by George Nachman on 9/21/14.
//
//

#import "iTermAboutWindowController.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"

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
        NSString *versionString = [NSString stringWithFormat: @"Build %@\n\n",
                                   myDict[(NSString *)kCFBundleVersionKey]];

        NSAttributedString *webAString = [self attributedStringWithLinkToURL:@"https://iterm2.com/"
                                                                       title:@"Home Page\n"];
        NSAttributedString *bugsAString =
                [self attributedStringWithLinkToURL:@"https://iterm2.com/bugs"
                                              title:@"Report a bug\n"];
        NSAttributedString *creditsAString =
                [self attributedStringWithLinkToURL:@"https://iterm2.com/credits"
                                              title:@"Credits"];

        // Force IBOutlets to be bound by creating window.
        [self window];

        [_dynamicText setLinkTextAttributes:self.linkTextViewAttributes];
        [[_dynamicText textStorage] deleteCharactersInRange:NSMakeRange(0, [[_dynamicText textStorage] length])];
        [[_dynamicText textStorage] appendAttributedString:[[[NSAttributedString alloc] initWithString:versionString] autorelease]];
        [[_dynamicText textStorage] appendAttributedString:webAString];
        [[_dynamicText textStorage] appendAttributedString:bugsAString];
        [[_dynamicText textStorage] appendAttributedString:creditsAString];
        [_dynamicText setAlignment:NSTextAlignmentCenter
                             range:NSMakeRange(0, [[_dynamicText textStorage] length])];

        [self setPatronsString:[self defaultPatronsString] animate:NO];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSURL *url = [NSURL URLWithString:@"https://iterm2.com/patrons.txt"];
            NSData *data = [NSData dataWithContentsOfURL:url];
            NSString *string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
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
              NSForegroundColorAttributeName: [NSColor blueColor],
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
    CGFloat diff = _patronsTextView.frame.size.height - rect.size.height;
    rect.size.height = _patronsTextView.frame.size.height;
    _patronsTextView.enclosingScrollView.frame = rect;

    rect = self.window.frame;
    rect.size.height += diff;
    [self.window setFrame:rect display:YES animate:animate];
}

- (NSAttributedString *)defaultPatronsString {
    NSString *string = [NSString stringWithFormat:@"Loading supporters…"];
    NSMutableAttributedString *attributedString =
        [[[NSMutableAttributedString alloc] initWithString:string] autorelease];
    return attributedString;
}

- (void)setPatrons:(NSArray *)patronNames {
    if (!patronNames.count) {
        [self setPatronsString:[[[NSAttributedString alloc] initWithString:@"Error loading patrons :("] autorelease] animate:NO];
        return;
    }

    NSArray *sortedNames = [patronNames sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        return [[obj1 surname] compare:[obj2 surname]];
    }];
    NSString *patrons = [sortedNames componentsJoinedWithOxfordComma];
    NSString *string = [NSString stringWithFormat:@"iTerm2 is generously supported by %@ on ", patrons];
    NSMutableAttributedString *attributedString =
        [[[NSMutableAttributedString alloc] initWithString:string] autorelease];
    NSAttributedString *patreonLink = [self attributedStringWithLinkToURL:@"https://patreon.com/gnachman"
                                                                    title:@"Patreon"];
    [attributedString appendAttributedString:patreonLink];
    NSAttributedString *period = [[[NSAttributedString alloc] initWithString:@"."] autorelease];
    [attributedString appendAttributedString:period];

    [self setPatronsString:attributedString animate:YES];
}

- (NSAttributedString *)attributedStringWithLinkToURL:(NSString *)urlString title:(NSString *)title {
    NSDictionary *linkAttributes = @{ NSLinkAttributeName: [NSURL URLWithString:urlString] };
    NSString *localizedTitle = title;
    return [[[NSAttributedString alloc] initWithString:localizedTitle
                                            attributes:linkAttributes] autorelease];
}

@end
