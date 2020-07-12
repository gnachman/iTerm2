//
//  iTermShellIntegrationFirstPageViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import "iTermShellIntegrationFirstPageViewController.h"

@interface iTermShellIntegrationFirstPageViewController ()
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@property (nonatomic, strong) IBOutlet NSButton *utilities;
@property (nonatomic, strong) IBOutlet NSTextField *descriptionLabel;
@property (nonatomic, strong) IBOutlet NSTextField *utilitiesLabel;
@end

@implementation iTermShellIntegrationFirstPageViewController
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
    [attributedString appendAttributedString:[self attributedStringWithLinkToURL:url title:@"Learn more."]];
}

- (void)viewDidLoad {
    NSNumber *number = [[NSUserDefaults standardUserDefaults] objectForKey:iTermShellIntegrationInstallUtilitiesUserDefaultsKey];
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
}

- (IBAction)toggleInstallUtilities:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.utilities.state == NSControlStateValueOn forKey:iTermShellIntegrationInstallUtilitiesUserDefaultsKey];
}

- (IBAction)next:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerSetInstallUtilities:self.utilities.state == NSControlStateValueOn];
    [self.shellInstallerDelegate shellIntegrationInstallerContinue];
}
@end
