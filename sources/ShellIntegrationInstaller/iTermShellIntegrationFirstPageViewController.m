//
//  iTermShellIntegrationFirstPageViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import "iTermShellIntegrationFirstPageViewController.h"
#import "DebugLogging.h"
#import "iTermUserDefaults.h"

@interface iTermShellIntegrationFirstPageViewController ()
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@property (nonatomic, strong) IBOutlet NSButton *utilities;
@property (nonatomic, strong) IBOutlet NSTextField *descriptionLabel;
@property (nonatomic, strong) IBOutlet NSTextField *utilitiesLabel;
@end

@implementation iTermShellIntegrationFirstPageViewController {
    // The utilities description's height in the nib, which is the least it ever gets.
    CGFloat _minimumUtilitiesLabelHeight;
}
static NSString *const iTermShellIntegrationInstallUtilitiesUserDefaultsKey = @"NoSyncInstallUtilities";

- (void)setBusy:(BOOL)busy {
}

- (NSAttributedString *)attributedStringWithFont:(NSFont *)font
                                          string:(NSString *)string {
    NSDictionary *attributes = @{ NSFontAttributeName: font };
    return [[NSAttributedString alloc] initWithString:string attributes:attributes];
}

- (NSAttributedString *)attributedStringWithLinkToURL:(NSURL *)url title:(NSString *)title {
    NSDictionary *linkAttributes = @{ NSLinkAttributeName: url };
    NSString *localizedTitle = title;
    return [[NSAttributedString alloc] initWithString:localizedTitle
                                           attributes:linkAttributes];
}

- (void)appendLearnMoreToAttributedString:(NSMutableAttributedString *)attributedString
                                      url:(NSURL *)url {
    [attributedString appendAttributedString:[self attributedStringWithLinkToURL:url title:NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.LearnMore", nil, [NSBundle mainBundle], @"Learn more.", @"Link text to learn more about shell integration")]];
}

- (void)viewDidLoad {
    NSNumber *number = [[iTermUserDefaults userDefaults] objectForKey:iTermShellIntegrationInstallUtilitiesUserDefaultsKey];
    BOOL installUtilities = number ? number.boolValue : YES;
    self.utilities.state = installUtilities ? NSControlStateValueOn : NSControlStateValueOff;

    NSMutableAttributedString *attributedString;
    attributedString = [[self attributedStringWithFont:_descriptionLabel.font
                                                string:_descriptionLabel.stringValue] mutableCopy];
    [self appendLearnMoreToAttributedString:attributedString
                                        url:[NSURL URLWithString:@"https://iterm2.com/documentation-shell-integration.html"]];
    _descriptionLabel.attributedStringValue = attributedString;
    
    attributedString = [[self attributedStringWithFont:_utilitiesLabel.font
                                                string:_utilitiesLabel.stringValue] mutableCopy];
    [self appendLearnMoreToAttributedString:attributedString
                                        url:[NSURL URLWithString:@"https://www.iterm2.com/documentation-utilities.html"]];
    _utilitiesLabel.attributedStringValue = attributedString;
    [self fitUtilitiesToContent];
}

// A translation of the utilities checkbox or its description can be longer than the English, so
// widen the checkbox up to the page’s margin and let the description wrap, growing the page upward
// so the buttons at the bottom stay where they are.
- (void)fitUtilitiesToContent {
    NSView *view = self.view;
    NSButton *checkbox = self.utilities;
    NSTextField *label = self.utilitiesLabel;
    if (!checkbox || !label) {
        return;
    }
    const CGFloat rightMargin = 18;

    NSRect checkboxFrame = checkbox.frame;
    const CGFloat maxCheckboxWidth = NSWidth(view.bounds) - NSMinX(checkboxFrame) - rightMargin;
    const CGFloat checkboxWidth = ceil(checkbox.cell.cellSize.width);
    checkboxFrame.size.width = MIN(maxCheckboxWidth, MAX(NSWidth(checkboxFrame), checkboxWidth));
    checkbox.frame = checkboxFrame;

    label.cell.wraps = YES;
    label.cell.lineBreakMode = NSLineBreakByWordWrapping;
    if (_minimumUtilitiesLabelHeight == 0) {
        _minimumUtilitiesLabelHeight = NSHeight(label.frame);
    }
    const NSRect labelFrame = label.frame;
    const NSRect measureBounds = NSMakeRect(0, 0, NSWidth(labelFrame), CGFLOAT_MAX);
    const CGFloat fittingHeight = ceil([label.cell cellSizeForBounds:measureBounds].height);
    const CGFloat delta = MAX(_minimumUtilitiesLabelHeight, fittingHeight) - NSHeight(labelFrame);
    if (delta == 0) {
        return;
    }
    DLog(@"Resize utilities description by %@ to fit text needing %@", @(delta), @(fittingHeight));
    const BOOL autoresizes = view.autoresizesSubviews;
    view.autoresizesSubviews = NO;
    NSRect viewFrame = view.frame;
    viewFrame.size.height += delta;
    // Keep the view's top edge where it is.
    viewFrame.origin.y -= delta;
    view.frame = viewFrame;
    view.autoresizesSubviews = autoresizes;
    for (NSView *subview in view.subviews) {
        if (subview == label) {
            continue;
        }
        if (NSMinY(subview.frame) >= NSMinY(labelFrame)) {
            NSRect frame = subview.frame;
            frame.origin.y += delta;
            subview.frame = frame;
        }
    }
    NSRect newLabelFrame = labelFrame;
    newLabelFrame.size.height += delta;
    label.frame = newLabelFrame;
}

- (IBAction)toggleInstallUtilities:(id)sender {
    [[iTermUserDefaults userDefaults] setBool:self.utilities.state == NSControlStateValueOn forKey:iTermShellIntegrationInstallUtilitiesUserDefaultsKey];
}

- (IBAction)next:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerSetInstallUtilities:self.utilities.state == NSControlStateValueOn];
    [self.shellInstallerDelegate shellIntegrationInstallerContinue];
}
@end
