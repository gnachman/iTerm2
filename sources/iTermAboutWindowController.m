//
//  iTermAboutWindowController.m
//  iTerm2
//
//  Created by George Nachman on 9/21/14.
//
//

#import "iTermAboutWindowController.h"

@implementation iTermAboutWindowController {
    IBOutlet NSTextView *_dynamicText;
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
                                              title:@"Credits"];

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
        [_dynamicText setAlignment: NSCenterTextAlignment range: NSMakeRange(0, [[_dynamicText textStorage] length])];
    }
    return self;
}

- (NSAttributedString *)attributedStringWithLinkToURL:(NSString *)urlString title:(NSString *)title {
    NSDictionary *linkAttributes = @{ NSLinkAttributeName: [NSURL URLWithString:urlString] };
    NSString *localizedTitle = title;
    return [[[NSAttributedString alloc] initWithString:localizedTitle
                                            attributes:linkAttributes] autorelease];
}

@end
