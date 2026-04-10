#import <XCTest/XCTest.h>
#import "PTYSession.h"

#import "ITAddressBookMgr.h"
#import "iTermPasteHelper.h"
#import "iTermProfilePreferences.h"
#import "iTermWarning.h"

typedef NSModalResponse (^WarningBlockType)(NSAlert *alert, NSString *identifier);

static NSDictionary *PTYSessionTestEncodedColor(CGFloat red, CGFloat green, CGFloat blue) {
    return [ITAddressBookMgr encodeColor:[NSColor colorWithCalibratedRed:red
                                                                   green:green
                                                                    blue:blue
                                                                   alpha:1]];
}

@interface FakePasteHelper : iTermPasteHelper
@property(nonatomic, copy) NSString *string;
@property(nonatomic) BOOL slowly;
@property(nonatomic) BOOL escapeShellChars;
@property(nonatomic) iTermTabTransformTags tabTransform;
@property(nonatomic) int spacesPerTab;
@end

@implementation FakePasteHelper

- (void)pasteString:(NSString *)theString
             slowly:(BOOL)slowly
   escapeShellChars:(BOOL)escapeShellChars
           isUpload:(BOOL)isUpload
    allowBracketing:(BOOL)allowBracketing
       tabTransform:(iTermTabTransformTags)tabTransform
       spacesPerTab:(int)spacesPerTab {
    self.string = theString;
    self.slowly = slowly;
    self.escapeShellChars = escapeShellChars;
    self.tabTransform = tabTransform;
    self.spacesPerTab = spacesPerTab;
}

- (void)dealloc {
    [_string release];
    [super dealloc];
}

@end

@interface PTYSessionTest : XCTestCase <iTermWarningHandler>
@end

@interface PTYSession (Internal)
- (void)setPasteHelper:(iTermPasteHelper *)pasteHelper;
@end

@implementation PTYSessionTest {
    PTYSession *_session;
    FakePasteHelper *_fakePasteHelper;
    WarningBlockType _warningBlock;
    NSMutableSet *_warningIdentifiers;
}

- (void)setUp {
    _session = [[PTYSession alloc] initSynthetic:NO];
    _fakePasteHelper = [[[FakePasteHelper alloc] init] autorelease];
    [_session setPasteHelper:_fakePasteHelper];
    _warningIdentifiers = [[NSMutableSet alloc] init];
    [iTermWarning setWarningHandler:self];
}

- (void)tearDown {
    [_session release];
    [_warningIdentifiers release];
}

- (void)testPasteEmptyString {
    [_session pasteString:@"" flags:0];
    XCTAssert(_fakePasteHelper.string == nil);
}

- (void)testBasicPaste {
    NSString *theString = @".";
    [_session pasteString:theString flags:0];
    XCTAssert([_fakePasteHelper.string isEqualToString:theString]);
    XCTAssert(_fakePasteHelper.tabTransform == kTabTransformNone);
    XCTAssert(!_fakePasteHelper.slowly);
    XCTAssert(!_fakePasteHelper.escapeShellChars);
}

- (void)testEscapeShellTabs {
    NSString *theString = @"\t";
    [_session pasteString:theString flags:kPTYSessionPasteWithShellEscapedTabs];
    XCTAssert([_fakePasteHelper.string isEqualToString:theString]);
    XCTAssert(_fakePasteHelper.tabTransform == kTabTransformEscapeWithCtrlV);
    XCTAssert(!_fakePasteHelper.slowly);
    XCTAssert(!_fakePasteHelper.escapeShellChars);
}

- (void)testPasteSlowly {
    NSString *theString = @".";
    [_session pasteString:theString flags:kPTYSessionPasteSlowly];
    XCTAssert([_fakePasteHelper.string isEqualToString:theString]);
    XCTAssert(_fakePasteHelper.tabTransform == kTabTransformNone);
    XCTAssert(_fakePasteHelper.slowly);
    XCTAssert(!_fakePasteHelper.escapeShellChars);
}

- (void)testEscapeSpecialChars {
    NSString *theString = @".";
    [_session pasteString:theString flags:kPTYSessionPasteEscapingSpecialCharacters];
    XCTAssert([_fakePasteHelper.string isEqualToString:theString]);
    XCTAssert(_fakePasteHelper.tabTransform == kTabTransformNone);
    XCTAssert(!_fakePasteHelper.slowly);
    XCTAssert(
           _fakePasteHelper.escapeShellChars);
}

- (void)testEmbeddedTabsConvertToSpaces {
    NSString *theString = @"a\tb";
    _warningBlock = ^NSModalResponse(NSAlert *alert, NSString *identifier) {
        XCTAssert([identifier isEqualToString:@"AboutToPasteTabsWithCancel"]);
        BOOL found = NO;
        for (NSView *subview in alert.accessoryView.subviews) {
            if ([subview isKindOfClass:[NSTextField class]] &&
                [(NSTextField *)subview isEditable]) {
                found = YES;
                NSTextField *textField = (NSTextField *)subview;
                textField.intValue = 8;
                [(id)textField.delegate controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification
                                                                                           object:nil]];
                break;
            }
        }
        XCTAssert(found);
        return NSAlertThirdButtonReturn;
    };
    [_session pasteString:theString flags:0];
    XCTAssert([_warningIdentifiers containsObject:@"AboutToPasteTabsWithCancel"]);

    XCTAssert([_fakePasteHelper.string isEqualToString:theString]);
    XCTAssert(_fakePasteHelper.tabTransform == kTabTransformConvertToSpaces);
    XCTAssert(!_fakePasteHelper.slowly);
    XCTAssert(!_fakePasteHelper.escapeShellChars);
    XCTAssert(_fakePasteHelper.spacesPerTab == 8);
}

- (void)testTabColorFallsBackToOppositeMode {
    NSDictionary *lightColor = PTYSessionTestEncodedColor(1, 0.25, 0);
    Profile *profile = @{
        KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @YES,
        KEY_USE_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX: @YES,
        KEY_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX: lightColor,
    };

    XCTAssertTrue([iTermProfilePreferences boolForTabColorKey:KEY_USE_TAB_COLOR dark:YES profile:profile]);
    XCTAssertEqualObjects([iTermProfilePreferences objectForTabColorKey:KEY_TAB_COLOR dark:YES profile:profile],
                          lightColor);
}

- (void)testTabColorPrefersCurrentModeWhenExplicitlySet {
    NSDictionary *lightColor = PTYSessionTestEncodedColor(1, 0.25, 0);
    NSDictionary *darkColor = PTYSessionTestEncodedColor(0.1, 0.2, 0.9);
    Profile *profile = @{
        KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @YES,
        KEY_USE_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX: @YES,
        KEY_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX: lightColor,
        KEY_USE_TAB_COLOR COLORS_DARK_MODE_SUFFIX: @YES,
        KEY_TAB_COLOR COLORS_DARK_MODE_SUFFIX: darkColor,
    };

    XCTAssertTrue([iTermProfilePreferences boolForTabColorKey:KEY_USE_TAB_COLOR dark:YES profile:profile]);
    XCTAssertEqualObjects([iTermProfilePreferences objectForTabColorKey:KEY_TAB_COLOR dark:YES profile:profile],
                          darkColor);
}

- (void)testTabColorFallsBackToSharedKey {
    NSDictionary *sharedColor = PTYSessionTestEncodedColor(0.4, 0.8, 0.2);
    Profile *profile = @{
        KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @YES,
        KEY_USE_TAB_COLOR: @YES,
        KEY_TAB_COLOR: sharedColor,
    };

    XCTAssertTrue([iTermProfilePreferences boolForTabColorKey:KEY_USE_TAB_COLOR dark:YES profile:profile]);
    XCTAssertEqualObjects([iTermProfilePreferences objectForTabColorKey:KEY_TAB_COLOR dark:YES profile:profile],
                          sharedColor);
}

- (void)testTabColorDoesNotFallBackPastExplicitDisabledMode {
    NSDictionary *lightColor = PTYSessionTestEncodedColor(1, 0.25, 0);
    Profile *profile = @{
        KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @YES,
        KEY_USE_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX: @YES,
        KEY_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX: lightColor,
        KEY_USE_TAB_COLOR COLORS_DARK_MODE_SUFFIX: @NO,
    };

    XCTAssertFalse([iTermProfilePreferences boolForTabColorKey:KEY_USE_TAB_COLOR dark:YES profile:profile]);
}

#pragma mark - iTermWarningHandler

- (NSModalResponse)warningWouldShowAlert:(NSAlert *)alert identifier:(NSString *)identifier {
    [_warningIdentifiers addObject:identifier];
    return _warningBlock(alert, identifier);
}

@end
