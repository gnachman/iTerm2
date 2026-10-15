//
//  ProfilesWindowButtonWidthTests.m
//  ModernTests
//
//  QA finding F-393: in Russian the Profiles window's New Tab button read
//  “Новая вкла…” because its fixed width suited English. These read the
//  buttons' frames from ProfilesWindow.xib in the source tree and check
//  that every shipped translation of each title fits.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

@interface ProfilesWindowButtonWidthTests : XCTestCase
@end

@implementation ProfilesWindowButtonWidthTests {
    NSXMLDocument *_xib;
}

- (void)setUp {
    NSString *source = [NSString stringWithUTF8String:__FILE__];
    NSString *xibPath = [[[source stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:@"sources/Settings/Base.lproj/ProfilesWindow.xib"];
    NSError *error = nil;
    _xib = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:xibPath] options:0 error:&error];
    XCTAssertNotNil(_xib, @"%@", error);
}

- (NSRect)frameOf:(NSString *)identifier {
    NSString *xpath = [NSString stringWithFormat:@"//*[@id='%@']/rect[@key='frame']", identifier];
    NSXMLElement *rect = [[_xib nodesForXPath:xpath error:nil] firstObject];
    XCTAssertNotNil(rect, @"No frame for %@", identifier);
    return NSMakeRect([rect attributeForName:@"x"].stringValue.doubleValue,
                      [rect attributeForName:@"y"].stringValue.doubleValue,
                      [rect attributeForName:@"width"].stringValue.doubleValue,
                      [rect attributeForName:@"height"].stringValue.doubleValue);
}

- (NSArray<NSString *> *)translationsOfKey:(NSString *)key {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *language in @[ @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"ProfilesWindow"
                                                         ofType:@"strings"
                                                    inDirectory:nil
                                                forLocalization:language];
        NSDictionary<NSString *, NSString *> *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
        XCTAssertNotNil(strings[key], @"No %@ for %@", key, language);
        if (strings[key]) {
            [result addObject:strings[key]];
        }
    }
    return result;
}

// Push buttons: the button's id and its cell's id (the catalog key).
- (void)testPushButtonTitlesFit {
    NSDictionary<NSString *, NSString *> *buttons = @{
        @"327": @"328",  // New Tab
        @"329": @"330",  // New Window
        @"339": @"340",  // New Tabs in New Window
        @"320": @"321",  // Edit Profiles…
    };
    for (NSString *buttonID in buttons) {
        const NSRect frame = [self frameOf:buttonID];
        NSString *key = [buttons[buttonID] stringByAppendingString:@".title"];
        for (NSString *title in [self translationsOfKey:key]) {
            NSButton *button = [NSButton buttonWithTitle:title target:nil action:nil];
            button.bezelStyle = NSBezelStyleRounded;
            button.frame = frame;
            XCTAssertLessThanOrEqual(ceil(button.cell.cellSize.width), NSWidth(frame), @"%@ clipped", title);
        }
    }
}

- (void)testWidenedButtonsStayClearOfTheirNeighbors {
    const NSRect newTab = [self frameOf:@"327"];
    XCTAssertLessThanOrEqual(NSMaxX([self frameOf:@"fpn-pw-btn"]), NSMinX(newTab));
    XCTAssertLessThanOrEqual(NSMaxX(newTab), NSMinX([self frameOf:@"329"]));
    XCTAssertLessThanOrEqual(NSMaxX([self frameOf:@"339"]), NSMinX([self frameOf:@"343"]));
}

@end
