#import "iTermTests.h"
#import "PTYSessionTest.h"
#import "PTYSession.h"

#import "iTermPasteHelper.h"
#import "iTermWarning.h"

typedef NSModalResponse (^WarningBlockType)(NSAlert *alert, NSString *identifier);

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
           commands:(BOOL)commands
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

@interface PTYSessionTest ()<iTermWarningHandler>
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

- (void)setup {
    _session = [[PTYSession alloc] init];
    _fakePasteHelper = [[[FakePasteHelper alloc] init] autorelease];
    [_session setPasteHelper:_fakePasteHelper];
    _warningIdentifiers = [[NSMutableSet alloc] init];
    [iTermWarning setWarningHandler:self];
}

- (void)teardown {
    [_session release];
    [_warningIdentifiers release];
}

- (void)testPasteEmptyString {
    [_session pasteString:@"" flags:0];
    assert(_fakePasteHelper.string == nil);
}

- (void)testBasicPaste {
    NSString *theString = @".";
    [_session pasteString:theString flags:0];
    assert([_fakePasteHelper.string isEqualToString:theString]);
    assert(_fakePasteHelper.tabTransform == kTabTransformNone);
    assert(!_fakePasteHelper.slowly);
    assert(!_fakePasteHelper.escapeShellChars);
}

- (void)testEscapeShellTabs {
    NSString *theString = @"\t";
    [_session pasteString:theString flags:kPTYSessionPasteWithShellEscapedTabs];
    assert([_fakePasteHelper.string isEqualToString:theString]);
    assert(_fakePasteHelper.tabTransform == kTabTransformEscapeWithCtrlV);
    assert(!_fakePasteHelper.slowly);
    assert(!_fakePasteHelper.escapeShellChars);
}

- (void)testPasteSlowly {
    NSString *theString = @".";
    [_session pasteString:theString flags:kPTYSessionPasteSlowly];
    assert([_fakePasteHelper.string isEqualToString:theString]);
    assert(_fakePasteHelper.tabTransform == kTabTransformNone);
    assert(_fakePasteHelper.slowly);
    assert(!_fakePasteHelper.escapeShellChars);
}

- (void)testEscapeSpecialChars {
    NSString *theString = @".";
    [_session pasteString:theString flags:kPTYSessionPasteEscapingSpecialCharacters];
    assert([_fakePasteHelper.string isEqualToString:theString]);
    assert(_fakePasteHelper.tabTransform == kTabTransformNone);
    assert(!_fakePasteHelper.slowly);
    assert(
           _fakePasteHelper.escapeShellChars);
}

- (void)testEmbeddedTabsConvertToSpaces {
    NSString *theString = @"a\tb";
    _warningBlock = ^NSModalResponse(NSAlert *alert, NSString *identifier) {
        assert([identifier isEqualToString:@"AboutToPasteTabsWithCancel"]);
        BOOL found = NO;
        for (NSView *subview in alert.accessoryView.subviews) {
            if ([subview isKindOfClass:[NSTextField class]] &&
                [(NSTextField *)subview isEditable]) {
                found = YES;
                NSTextField *textField = (NSTextField *)subview;
                textField.intValue = 8;
                [(id)textField.delegate controlTextDidChange:nil];
                break;
            }
        }
        assert(found);
        return NSAlertOtherReturn;
    };
    [_session pasteString:theString flags:0];
    assert([_warningIdentifiers containsObject:@"AboutToPasteTabsWithCancel"]);

    assert([_fakePasteHelper.string isEqualToString:theString]);
    assert(_fakePasteHelper.tabTransform == kTabTransformConvertToSpaces);
    assert(!_fakePasteHelper.slowly);
    assert(!_fakePasteHelper.escapeShellChars);
    assert(_fakePasteHelper.spacesPerTab == 8);
}

#pragma mark - iTermWarningHandler

- (NSModalResponse)warningWouldShowAlert:(NSAlert *)alert identifier:(NSString *)identifier {
    [_warningIdentifiers addObject:identifier];
    return _warningBlock(alert, identifier);
}

@end