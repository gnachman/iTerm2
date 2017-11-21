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
#if 0
        NSString *versionString = [NSString stringWithFormat: @"Build %@\n\n",
                                   myDict[(NSString *)kCFBundleVersionKey]];
#endif
        NSString *versionString = [NSString stringWithFormat: @"Version 0.0.5\niTerm2 fork by pancake\n\n"];

        NSAttributedString *webAString = [self attributedStringWithLinkToURL:@"https://github.com/trufae/Therm"
                                                                       title:@"Home Page\n"];
        NSAttributedString *bugsAString =
                [self attributedStringWithLinkToURL:@"https://github.com/trufae/Therm/issues"
                                              title:@"Report a bug\n"];

        // Force IBOutlets to be bound by creating window.
        [self window];

        [_dynamicText setLinkTextAttributes:self.linkTextViewAttributes];
        [[_dynamicText textStorage] deleteCharactersInRange:NSMakeRange(0, [[_dynamicText textStorage] length])];
        [[_dynamicText textStorage] appendAttributedString:[[[NSAttributedString alloc] initWithString:versionString] autorelease]];
        [[_dynamicText textStorage] appendAttributedString:webAString];
        [[_dynamicText textStorage] appendAttributedString:bugsAString];
        [_dynamicText setAlignment:NSCenterTextAlignment
                             range:NSMakeRange(0, [[_dynamicText textStorage] length])];
    }
    return self;
}

- (NSDictionary *)linkTextViewAttributes {
    return @{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
              NSForegroundColorAttributeName: [NSColor blueColor],
              NSCursorAttributeName: [NSCursor pointingHandCursor] };
}

- (void)setPatronsString:(NSAttributedString *)patronsAttributedString animate:(BOOL)animate {
}

- (NSAttributedString *)defaultPatronsString {
    return nil;
}

- (void)setPatrons:(NSArray *)patronNames {
    return;
}

- (NSAttributedString *)attributedStringWithLinkToURL:(NSString *)urlString title:(NSString *)title {
    NSDictionary *linkAttributes = @{ NSLinkAttributeName: [NSURL URLWithString:urlString] };
    NSString *localizedTitle = title;
    return [[[NSAttributedString alloc] initWithString:localizedTitle
                                            attributes:linkAttributes] autorelease];
}

@end
