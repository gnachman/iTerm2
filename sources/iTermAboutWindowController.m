//
//  iTermAboutWindowController.m
//  iTerm2
//
//  Created by George Nachman on 9/21/14.
//
//

#import "iTermAboutWindowController.h"
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
                                              title:@"Report a bug\n\n"];
        NSAttributedString *creditsAString =
                [self attributedStringWithLinkToURL:@"https://iterm2.com/credits"
                                              title:@"Credits\n\n"];

        NSDictionary *linkTextViewAttributes = @{ NSUnderlineStyleAttributeName: @(NSSingleUnderlineStyle),
                                                  NSForegroundColorAttributeName: [NSColor blueColor],
                                                  NSCursorAttributeName: [NSCursor pointingHandCursor] };

        // Force IBOutlets to be bound by creating window.
        [self window];
        
        [_dynamicText setLinkTextAttributes:linkTextViewAttributes];
        [[_dynamicText textStorage] deleteCharactersInRange:NSMakeRange(0, [[_dynamicText textStorage] length])];
        [[_dynamicText textStorage] appendAttributedString:[[[NSAttributedString alloc] initWithString:versionString] autorelease]];
        [[_dynamicText textStorage] appendAttributedString:webAString];
        [[_dynamicText textStorage] appendAttributedString:bugsAString];
        [[_dynamicText textStorage] appendAttributedString:creditsAString];
        [_dynamicText setAlignment:NSCenterTextAlignment
                             range:NSMakeRange(0, [[_dynamicText textStorage] length])];

        NSAttributedString *patronsAttributedString = [self patronsString];
        [_patronsTextView setLinkTextAttributes:linkTextViewAttributes];
        [[_patronsTextView textStorage] deleteCharactersInRange:NSMakeRange(0, [[_patronsTextView textStorage] length])];
        [[_patronsTextView textStorage] appendAttributedString:patronsAttributedString];
        [_patronsTextView setAlignment:NSLeftTextAlignment
                             range:NSMakeRange(0, [[_patronsTextView textStorage] length])];
        _patronsTextView.horizontallyResizable = NO;

        NSRect rect = _patronsTextView.frame;
        NSDictionary *attributes = [patronsAttributedString attributesAtIndex:0 effectiveRange:nil];
        CGFloat fittingHeight =
            [[[_patronsTextView textStorage] string] heightWithAttributes:attributes
                                                       constrainedToWidth:rect.size.width];
        CGFloat diff = fittingHeight - rect.size.height;
        rect.size.height = fittingHeight;
        [_patronsTextView sizeToFit];

        rect = self.window.frame;
        rect.size.height += diff;
        [self.window setFrame:rect display:YES];


    }
    return self;
}

- (NSAttributedString *)patronsString {
    NSString *patrons = @"Aaron Kulbe, Filip, Ozzy Johnson, and Stefan Countryman";
    NSString *string = [NSString stringWithFormat:@"iTerm2 is generously supported by %@ on ", patrons];
    NSMutableAttributedString *attributedString =
        [[[NSMutableAttributedString alloc] initWithString:string] autorelease];
    NSAttributedString *patreonLink = [self attributedStringWithLinkToURL:@"https://patreon.com/gnachman"
                                                                    title:@"Patreon"];
    [attributedString appendAttributedString:patreonLink];
    NSAttributedString *period = [[[NSAttributedString alloc] initWithString:@"."] autorelease];
    [attributedString appendAttributedString:period];

    return attributedString;
}

- (NSAttributedString *)attributedStringWithLinkToURL:(NSString *)urlString title:(NSString *)title {
    NSDictionary *linkAttributes = @{ NSLinkAttributeName: [NSURL URLWithString:urlString] };
    NSString *localizedTitle = title;
    return [[[NSAttributedString alloc] initWithString:localizedTitle
                                            attributes:linkAttributes] autorelease];
}

@end
