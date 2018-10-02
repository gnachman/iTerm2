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
#include "../config.h"

@implementation iTermAboutWindowController {
    IBOutlet NSTextView *_dynamicText;
    IBOutlet NSTextView *_patronsTextView;
    IBOutlet NSTextField *_titleText;
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
#if 0
        NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];
        NSString *versionString = [NSString stringWithFormat: @"Build %@\n\n", myDict[(NSString *)kCFBundleVersionKey]];
#endif
     
        NSString *versionString = [NSString stringWithFormat:@"iTerm2 fork by pancake\n\n"];
        [_titleText setStringValue: @"Therm " THERM_VERSION];
        NSAttributedString *webAString = [self attributedStringWithLinkToURL:@"https://github.com/trufae/Therm" title:@"\nvisit Github\n"];
        
#if 0
        NSAttributedString *bugsAString =
                [self attributedStringWithLinkToURL:@"https://github.com/trufae/Therm/issues"
                                              title:@"Report a bug\n"];

        // Force IBOutlets to be bound by creating window.
        [self window];
        
#endif
        [[self window] setLevel:NSFloatingWindowLevel];

        [_dynamicText setLinkTextAttributes:self.linkTextViewAttributes];
        NSTextStorage *ts = [_dynamicText textStorage];
        
        [ts deleteCharactersInRange:NSMakeRange(0, [ts length])];
       // NSFont *font = [NSFont fontWithName:@"Palatino-Roman" size:14.0];
        NSColor *color = [NSColor grayColor];
       // NSDictionary *asa = [NSDictionary dictionaryWithObject: font forKey: NSFontAttributeName];
        NSDictionary *asa = [NSDictionary dictionaryWithObject: color forKey: NSForegroundColorAttributeName];

     //   NSAttributedString *as = [[[NSAttributedString alloc] initWithString:versionString] autorelease];
        NSAttributedString *as = [[NSAttributedString alloc] initWithString: versionString attributes:asa];
        
        //                          alloc] initWithString:versionString] autorelease];

        [ts appendAttributedString: as];
        [ts appendAttributedString: webAString];
       // [[_dynamicText textStorage] appendAttributedString:bugsAString];
        [_dynamicText setAlignment:NSCenterTextAlignment
                             range:NSMakeRange(0, [[_dynamicText textStorage] length])];
        [_titleText setStringValue: [@"Therm v" stringByAppendingString: @THERM_VERSION]];
    }
    return self;
}

- (NSDictionary *)linkTextViewAttributes {
    NSColor *linkColor = [NSColor grayColor];
    return @{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
              NSForegroundColorAttributeName: linkColor,
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
