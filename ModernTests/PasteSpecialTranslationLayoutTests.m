//
//  PasteSpecialTranslationLayoutTests.m
//  ModernTests
//
//  QA finding F-302: in Russian, Advanced Paste clipped its section header,
//  the chunk size and delay titles (which ran into their values), the
//  Minimum Duration title, the regular expression placeholder, and the
//  substitution help text. These give the real views every shipped
//  translation and check that each one fits.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

@protocol PasteSpecialViewControllerLayoutForTesting <NSObject>
@property(nonatomic, readonly) NSView *view;
- (void)layoutSpeedLabels;
- (IBAction)chunkSizeDidChange:(id)sender;
- (IBAction)delayBetweenChunksDidChange:(id)sender;
- (void)layoutForTranslations;
@end

@protocol PasteSpecialWindowControllerLayoutForTesting <NSObject>
- (void)layoutEstimatedDurationLabels;
@end

// Stands in for iTermPasteSpecialWindowController as the window nib's owner,
// so the nib can be loaded without running the controller's -awakeFromNib.
@interface PasteSpecialWindowNibOwnerForTesting : NSObject {
@public
    NSTextField *_statsLabel;
    NSPopUpButton *_itemList;
    NSTextView *_preview;
    NSTextField *_estimatedDuration;
    NSTextField *_estimatedDurationTitle;
    NSView *_terminalModeEnclosure;
    NSView *_pasteSpecialViewContainer;
}
@property(nonatomic, strong) NSWindow *window;
@end

@implementation PasteSpecialWindowNibOwnerForTesting
- (IBAction)ok:(id)sender {}
- (IBAction)cancel:(id)sender {}
- (IBAction)selectItem:(id)sender {}
@end

@interface PasteSpecialTranslationLayoutTests : XCTestCase
@end

@implementation PasteSpecialTranslationLayoutTests {
    NSArray *_topLevelObjects;
}

+ (NSArray<NSString *> *)languages {
    return @[ @"cs", @"da", @"de", @"el", @"es", @"fi", @"fr", @"hr", @"hu", @"id", @"it", @"ja", @"nb", @"nl", @"pl", @"pt-BR", @"ro", @"ru", @"sk", @"sl", @"sv", @"tr", @"uk", @"vi", @"zh-Hans", @"zh-Hant" ];
}

- (NSString *)stringForKey:(NSString *)key table:(NSString *)table language:(NSString *)language {
    NSString *path = [[NSBundle mainBundle] pathForResource:table
                                                     ofType:@"strings"
                                                inDirectory:nil
                                            forLocalization:language];
    NSDictionary<NSString *, NSString *> *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    XCTAssertNotNil(strings[key], @"No %@ in %@ for %@", key, table, language);
    return strings[key] ?: @"";
}

- (NSString *)viewControllerString:(NSString *)key language:(NSString *)language {
    return [self stringForKey:key table:@"iTermPasteSpecialViewController" language:language];
}

- (id<PasteSpecialViewControllerLayoutForTesting>)newViewController {
    Class theClass = NSClassFromString(@"iTermPasteSpecialViewController");
    XCTAssertNotNil(theClass);
    id<PasteSpecialViewControllerLayoutForTesting> vc = [[theClass alloc] init];
    XCTAssertNotNil(vc.view);
    return vc;
}

- (id)outlet:(NSString *)name of:(id)object {
    id value = nil;
    @try {
        value = [(NSObject *)object valueForKey:name];
    } @catch (NSException *exception) {
        XCTFail(@"No outlet %@: %@", name, exception);
    }
    return value;
}

// Every text field in `view` whose text is `string`.
- (NSTextField *)textFieldIn:(NSView *)view withString:(NSString *)string {
    for (NSView *subview in view.subviews) {
        if ([subview isKindOfClass:NSTextField.class] &&
            [[(NSTextField *)subview stringValue] isEqualToString:string]) {
            return (NSTextField *)subview;
        }
        NSTextField *found = [self textFieldIn:subview withString:string];
        if (found) {
            return found;
        }
    }
    return nil;
}

// Keeps the field's text attributes, since a hyperlink label carries its font
// in its attributed string rather than in the field.
- (CGFloat)widthNeededByField:(NSTextField *)field toShow:(NSString *)string {
    NSAttributedString *saved = field.attributedStringValue;
    NSDictionary *attributes = saved.length ? [saved attributesAtIndex:0 effectiveRange:nil] : @{};
    field.attributedStringValue = [[NSAttributedString alloc] initWithString:string attributes:attributes];
    const CGFloat width = ceil([field.cell cellSizeForBounds:NSMakeRect(0, 0, CGFLOAT_MAX, NSHeight(field.frame))].width);
    field.attributedStringValue = saved;
    return width;
}

// The value label's widest text over every stop of `slider`.
- (CGFloat)widestValueOf:(NSTextField *)valueLabel
                  slider:(NSSlider *)slider
                  action:(void (^)(NSSlider *))action {
    CGFloat widest = 0;
    for (NSInteger i = 0; i < slider.numberOfTickMarks; i++) {
        slider.doubleValue = [slider tickMarkValueAtIndex:i];
        action(slider);
        widest = MAX(widest, [self widthNeededByField:valueLabel toShow:valueLabel.stringValue]);
    }
    return widest;
}

- (void)assertTitle:(NSTextField *)title
             string:(NSString *)string
         valueLabel:(NSTextField *)valueLabel
       widestValue:(CGFloat)widestValue
               maxX:(CGFloat)maxX
           language:(NSString *)language {
    XCTAssertGreaterThanOrEqual(NSWidth(title.frame), [self widthNeededByField:title toShow:string],
                                @"%@ title clipped: %@", language, string);
    XCTAssertGreaterThanOrEqual(NSMinX(valueLabel.frame), NSMaxX(title.frame),
                                @"%@: the value overlaps %@", language, string);
    XCTAssertLessThanOrEqual(NSMinX(valueLabel.frame) + widestValue, maxX,
                             @"%@: the value after %@ runs past the slider", language, string);
}

- (void)testSpeedTitlesAndValuesFit {
    for (NSString *language in [PasteSpecialTranslationLayoutTests languages]) {
        id<PasteSpecialViewControllerLayoutForTesting> vc = [self newViewController];
        NSTextField *chunkTitle = [self outlet:@"chunkSizeTitle" of:vc];
        NSTextField *delayTitle = [self outlet:@"delayBetweenChunksTitle" of:vc];
        NSTextField *chunkValue = [self outlet:@"chunkSizeLabel" of:vc];
        NSTextField *delayValue = [self outlet:@"delayBetweenChunksLabel" of:vc];
        NSSlider *chunkSlider = [self outlet:@"chunkSizeSlider" of:vc];
        NSSlider *delaySlider = [self outlet:@"delayBetweenChunksSlider" of:vc];
        if (!chunkTitle || !delayTitle) {
            return;
        }
        NSString *chunkString = [self viewControllerString:@"gmQ-6D-hd3.title" language:language];
        NSString *delayString = [self viewControllerString:@"oIL-MU-4nf.title" language:language];
        chunkTitle.stringValue = chunkString;
        delayTitle.stringValue = delayString;
        [vc layoutSpeedLabels];

        const CGFloat widestChunk = [self widestValueOf:chunkValue slider:chunkSlider action:^(NSSlider *slider) {
            [vc chunkSizeDidChange:slider];
        }];
        const CGFloat widestDelay = [self widestValueOf:delayValue slider:delaySlider action:^(NSSlider *slider) {
            [vc delayBetweenChunksDidChange:slider];
        }];
        [self assertTitle:chunkTitle string:chunkString valueLabel:chunkValue widestValue:widestChunk
                     maxX:NSMaxX(chunkSlider.frame) language:language];
        [self assertTitle:delayTitle string:delayString valueLabel:delayValue widestValue:widestDelay
                     maxX:NSMaxX(delaySlider.frame) language:language];
        XCTAssertLessThanOrEqual(NSMaxX(chunkValue.frame), NSMinX(delayTitle.frame),
                                 @"%@: the chunk size value runs into the delay title", language);
    }
}

- (void)testEnglishSpeedLayoutIsUnchanged {
    id<PasteSpecialViewControllerLayoutForTesting> vc = [self newViewController];
    XCTAssertEqual(NSMinX([[self outlet:@"chunkSizeLabel" of:vc] frame]), 116);
    XCTAssertEqual(NSMinX([[self outlet:@"delayBetweenChunksLabel" of:vc] frame]), 369);
    // English titles fit the nib, so the translation layout moves nothing.
    XCTAssertEqual(NSWidth(vc.view.frame), 444);
    XCTAssertTrue(NSEqualRects([[self outlet:@"escapeShellCharsWithBackslash" of:vc] frame], NSMakeRect(235, 274, 207, 18)));
    XCTAssertTrue(NSEqualRects([[self outlet:@"convertNewlines" of:vc] frame], NSMakeRect(-2, 274, 228, 18)));
    XCTAssertTrue(NSEqualRects([[self outlet:@"tabTransform" of:vc] frame], NSMakeRect(0, 0, 196, 58)));
    XCTAssertTrue(NSEqualRects([[self outlet:@"useRegexSubstitution" of:vc] frame], NSMakeRect(-2, 158, 84, 18)));
}

// Labels whose frames are fixed in the nib. Keys are the English text, which
// is how the test finds them in the English nib; values are catalog keys.
- (void)testFixedLabelsFit {
    NSDictionary<NSString *, NSString *> *labels = @{
        @"Transforms": @"IOU-ld-y0b.title",
        @"Use $1, $2, etc. for capture groups": @"tpG-Jk-bWC.title",
        @"Respects vim escape sequences": @"a9K-ff-GBV.title",
        @"ICU regular expression syntax": @"Iuq-a0-6jh.title",
    };
    for (NSString *english in labels) {
        id<PasteSpecialViewControllerLayoutForTesting> vc = [self newViewController];
        NSTextField *field = [self textFieldIn:vc.view withString:english];
        XCTAssertNotNil(field, @"No label %@", english);
        for (NSString *language in [PasteSpecialTranslationLayoutTests languages]) {
            NSString *string = [self viewControllerString:labels[english] language:language];
            XCTAssertLessThanOrEqual([self widthNeededByField:field toShow:string], NSWidth(field.frame),
                                     @"%@ clipped: %@", language, string);
        }
        XCTAssertLessThanOrEqual(NSMaxX(field.frame), NSWidth(vc.view.frame), @"%@ runs off the view", english);
    }
}

// Every NSButton in `view` whose title is `title`, searching subviews.
- (NSButton *)buttonIn:(NSView *)view withTitle:(NSString *)title {
    for (NSView *subview in view.subviews) {
        if ([subview isKindOfClass:NSButton.class] && [[(NSButton *)subview title] isEqualToString:title]) {
            return (NSButton *)subview;
        }
        NSButton *found = [self buttonIn:subview withTitle:title];
        if (found) {
            return found;
        }
    }
    return nil;
}

// Checkbox titles in the order the test applies them: English -> catalog key.
+ (NSDictionary<NSString *, NSString *> *)checkboxKeys {
    return @{
        @"Replace": @"65A-9c-omm.title",
        @"Convert CRLF and LF to CR": @"YGo-el-jcx.title",
        @"Escape shell characters with \\": @"geX-hg-c5A.title",
        @"Remove newlines": @"TcS-Fq-kZn.title",
        @"Convert Unicode punctuation": @"a6z-Q5-O3y.title",
        @"Base-64 encode": @"YXc-NP-geE.title",
        @"Bracketed paste mode": @"vTr-f3-LoJ.title",
        @"Remove unsafe control codes": @"Nc9-bk-vWI.title",
        @"Wait for shell prompt before pasting each line": @"nQ4-xf-lMs.title",
    };
}

+ (NSDictionary<NSString *, NSString *> *)radioKeys {
    return @{
        @"Paste with tabs": @"9FR-lE-vZJ.title",
        @"Convert tabs to spaces:": @"EeN-We-9AA.title",
        @"Escape tabs with ^V": @"8UF-96-NRu.title",
    };
}

// A view controller showing `language`'s checkbox and radio titles, laid out
// for them. Fills `checkboxes` with the checkboxes by English title.
- (id<PasteSpecialViewControllerLayoutForTesting>)viewControllerTranslatedTo:(NSString *)language
                                                                   checkboxes:(NSMutableDictionary<NSString *, NSButton *> *)checkboxes {
    id<PasteSpecialViewControllerLayoutForTesting> vc = [self newViewController];
    NSDictionary<NSString *, NSString *> *checkboxKeys = [PasteSpecialTranslationLayoutTests checkboxKeys];
    for (NSString *english in checkboxKeys) {
        NSButton *checkbox = [self buttonIn:vc.view withTitle:english];
        XCTAssertNotNil(checkbox, @"No checkbox %@", english);
        checkbox.title = [self viewControllerString:checkboxKeys[english] language:language];
        if (checkbox) {
            checkboxes[english] = checkbox;
        }
    }
    NSMatrix *matrix = [self outlet:@"tabTransform" of:vc];
    NSDictionary<NSString *, NSString *> *radioKeys = [PasteSpecialTranslationLayoutTests radioKeys];
    for (NSInteger row = 0; row < matrix.numberOfRows; row++) {
        NSButtonCell *cell = [matrix cellAtRow:row column:0];
        NSString *key = radioKeys[cell.title];
        XCTAssertNotNil(key, @"Unexpected radio %@", cell.title);
        if (key) {
            cell.title = [self viewControllerString:key language:language];
        }
    }
    [vc layoutForTranslations];
    return vc;
}

// French clipped “Échapper les caractères du…”, “Convertir la ponctuation
// Uni…”, “Supprimer les codes de cont…”, and “Rempla…”, and other languages
// clipped more. The columns widen to fit every checkbox title without the
// columns running into each other or off the view.
- (void)testCheckboxTitlesFit {
    for (NSString *language in [PasteSpecialTranslationLayoutTests languages]) {
        NSMutableDictionary<NSString *, NSButton *> *checkboxes = [NSMutableDictionary dictionary];
        id<PasteSpecialViewControllerLayoutForTesting> vc = [self viewControllerTranslatedTo:language checkboxes:checkboxes];
        NSView *view = vc.view;
        for (NSString *english in checkboxes) {
            NSButton *checkbox = checkboxes[english];
            XCTAssertLessThanOrEqual(ceil(checkbox.cell.cellSize.width), NSWidth(checkbox.frame),
                                     @"%@ clipped: %@", language, checkbox.title);
            const NSRect frame = [checkbox.superview convertRect:checkbox.frame toView:view];
            XCTAssertLessThanOrEqual(NSMaxX(frame), NSWidth(view.bounds), @"%@: %@ runs off the view", language, checkbox.title);
        }
        for (NSArray<NSString *> *pair in @[ @[ @"Convert CRLF and LF to CR", @"Escape shell characters with \\" ],
                                             @[ @"Remove newlines", @"Convert Unicode punctuation" ],
                                             @[ @"Bracketed paste mode", @"Remove unsafe control codes" ] ]) {
            NSButton *left = checkboxes[pair[0]];
            NSButton *right = checkboxes[pair[1]];
            XCTAssertLessThanOrEqual(NSMaxX([left.superview convertRect:left.frame toView:view]),
                                     NSMinX([right.superview convertRect:right.frame toView:view]),
                                     @"%@: %@ runs into %@", language, left.title, right.title);
        }
        NSButton *replace = checkboxes[@"Replace"];
        NSTextField *regex = [self outlet:@"regex" of:vc];
        XCTAssertLessThanOrEqual(NSMaxX(replace.frame), NSMinX(regex.frame), @"%@: Replace runs into the regex field", language);
    }
}

// The tab-handling radio buttons share one cell width, and the number of
// spaces field sits on the Convert row, so that title ends where the field
// begins. The matrix may not grow over the field or the stepper, which it
// would otherwise hide from clicks. French clipped “Convertir les tabulations
// e…” and “Échapper les tabulations a…”.
- (void)testTabRadioTitlesFit {
    for (NSString *language in [PasteSpecialTranslationLayoutTests languages]) {
        id<PasteSpecialViewControllerLayoutForTesting> vc =
            [self viewControllerTranslatedTo:language checkboxes:[NSMutableDictionary dictionary]];
        NSMatrix *matrix = [self outlet:@"tabTransform" of:vc];
        NSTextField *spaces = [self outlet:@"spacesPerTab" of:vc];
        NSStepper *stepper = [self outlet:@"stepper" of:vc];
        XCTAssertEqual(matrix.superview, spaces.superview);
        XCTAssertLessThanOrEqual(NSMaxX(matrix.frame), NSMinX(spaces.frame) + 4,
                                 @"%@: the radio buttons cover the spaces field", language);
        XCTAssertLessThanOrEqual(NSMaxX(spaces.frame), NSMinX(stepper.frame), @"%@", language);
        XCTAssertLessThanOrEqual(NSMaxX(stepper.frame), NSWidth(stepper.superview.bounds), @"%@", language);
        for (NSInteger row = 0; row < matrix.numberOfRows; row++) {
            NSButtonCell *cell = [matrix cellAtRow:row column:0];
            const NSRect rowFrame = [matrix convertRect:[matrix cellFrameAtRow:row column:0] toView:matrix.superview];
            CGFloat room = NSWidth(rowFrame);
            if (NSMaxY(spaces.frame) > NSMinY(rowFrame) && NSMinY(spaces.frame) < NSMaxY(rowFrame)) {
                room = MIN(room, NSMinX(spaces.frame) - NSMinX(rowFrame));
            }
            XCTAssertLessThanOrEqual(ceil(cell.cellSize.width), room, @"%@ clipped: %@", language, cell.title);
        }
    }
}

- (void)testRegexPlaceholderFits {
    id<PasteSpecialViewControllerLayoutForTesting> vc = [self newViewController];
    NSTextField *regex = [self outlet:@"regex" of:vc];
    NSTextFieldCell *cell = regex.cell;
    const CGFloat room = NSWidth([cell drawingRectForBounds:regex.bounds]);
    for (NSString *language in [PasteSpecialTranslationLayoutTests languages]) {
        NSString *string = [self viewControllerString:@"Qmg-L3-fKu.placeholderString" language:language];
        const CGFloat width = ceil([string sizeWithAttributes:@{ NSFontAttributeName: regex.font }].width);
        XCTAssertLessThanOrEqual(width, room, @"%@ placeholder clipped: %@", language, string);
    }
}

- (void)testMinimumDurationTitleFits {
    for (NSString *language in [PasteSpecialTranslationLayoutTests languages]) {
        PasteSpecialWindowNibOwnerForTesting *owner = [[PasteSpecialWindowNibOwnerForTesting alloc] init];
        NSNib *nib = [[NSNib alloc] initWithNibNamed:@"iTermPasteSpecialWindow" bundle:[NSBundle mainBundle]];
        NSArray *objects = nil;
        XCTAssertTrue([nib instantiateWithOwner:owner topLevelObjects:&objects]);
        _topLevelObjects = objects;
        NSTextField *title = owner->_estimatedDurationTitle;
        NSTextField *value = owner->_estimatedDuration;
        XCTAssertNotNil(title, @"No outlet for the Minimum duration title");
        XCTAssertNotNil(value);
        if (!title) {
            return;
        }
        NSString *string = [self stringForKey:@"Vi3-0q-5iR.title" table:@"iTermPasteSpecialWindow" language:language];
        title.stringValue = string;

        Class controllerClass = NSClassFromString(@"iTermPasteSpecialWindowController");
        // Not initialized: only its layout method is needed.
        id controller = [controllerClass alloc];
        [controller setValue:value forKey:@"_estimatedDuration"];
        [controller setValue:title forKey:@"_estimatedDurationTitle"];
        [(id<PasteSpecialWindowControllerLayoutForTesting>)controller layoutEstimatedDurationLabels];

        XCTAssertGreaterThanOrEqual(NSWidth(title.frame), [self widthNeededByField:title toShow:string],
                                    @"%@ title clipped: %@", language, string);
        XCTAssertGreaterThanOrEqual(NSMinX(value.frame), NSMaxX(title.frame), @"%@: overlap", language);
        NSString *instant = [self stringForKey:@"PasteSpecial.InstantDuration" table:@"Localizable" language:language];
        XCTAssertLessThanOrEqual(NSMinX(value.frame) + [self widthNeededByField:value toShow:instant],
                                 NSWidth(value.superview.frame),
                                 @"%@: the estimate runs out of its row", language);
    }
}

@end
