//
//  HotkeySettingsLabelLayoutTests.m
//  ModernTests
//
//  QA finding F-234: in Settings > Keys > Hotkey the right-aligned labels
//  were 263 points wide and ran under the controls beside them, so the colon
//  of “App Hotkey:” was drawn under its checkbox and “Open Quickly Hotkey:”
//  touched its shortcut field. These read PreferencePanel.xib from the
//  source tree and check that each label ends before the control on its row
//  and still fits every shipped translation.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

@interface HotkeySettingsLabelLayoutTests : XCTestCase
@end

@implementation HotkeySettingsLabelLayoutTests {
    NSXMLDocument *_xib;
}

- (void)setUp {
    NSString *source = [NSString stringWithUTF8String:__FILE__];
    NSString *xibPath = [[[source stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:@"sources/Settings/Base.lproj/PreferencePanel.xib"];
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

// Label id -> the id of the control on its row.
+ (NSDictionary<NSString *, NSString *> *)controlsByLabel {
    return @{
        @"32c-Yw-C1S": @"yqL-PV-QBa",  // Hotkey Window: / Create a Dedicated Hotkey Window…
        @"5106": @"5104",              // App Hotkey: / Show/hide all windows… checkbox
        @"v4W-f1-neV": @"7UJ-bR-mOm",  // Open Quickly Hotkey: / shortcut field
    };
}

- (void)testLabelsEndBeforeTheirControls {
    NSDictionary *pairs = [HotkeySettingsLabelLayoutTests controlsByLabel];
    for (NSString *labelID in pairs) {
        const NSRect label = [self frameOf:labelID];
        const NSRect control = [self frameOf:pairs[labelID]];
        XCTAssertLessThanOrEqual(NSMaxX(label) + 4, NSMinX(control), @"%@ runs under %@", labelID, pairs[labelID]);
    }
}

- (void)testLabelsFitEveryTranslation {
    // Label id -> its cell's id, the catalog key.
    NSDictionary<NSString *, NSString *> *cells = @{
        @"32c-Yw-C1S": @"IKL-nD-a5S",
        @"5106": @"5113",
        @"v4W-f1-neV": @"BAw-ed-Of1",
    };
    for (NSString *language in @[ @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"PreferencePanel"
                                                         ofType:@"strings"
                                                    inDirectory:nil
                                                forLocalization:language];
        NSDictionary<NSString *, NSString *> *strings = [NSDictionary dictionaryWithContentsOfFile:path];
        for (NSString *labelID in cells) {
            NSString *title = strings[[cells[labelID] stringByAppendingString:@".title"]];
            XCTAssertNotNil(title, @"%@ %@", language, labelID);
            NSTextField *label = [NSTextField labelWithString:title ?: @""];
            label.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
            XCTAssertLessThanOrEqual(ceil(label.cell.cellSize.width), NSWidth([self frameOf:labelID]),
                                     @"%@ clipped: %@", language, title);
        }
    }
}

@end
