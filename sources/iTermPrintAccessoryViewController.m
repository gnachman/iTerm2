//
//  iTermPrintAccessoryViewController.m
//  iTerm2
//
//  Created by George Nachman on 11/19/15.
//
//

#import "iTermPrintAccessoryViewController.h"

static NSString *const kBlackAndWhiteKey = @"Print In Black And White";

@implementation iTermPrintAccessoryViewController

- (void)dealloc {
    [_userDidChangeSetting release];
    [super dealloc];
}

- (NSArray<NSDictionary<NSString *,NSString *> *> *)localizedSummaryItems {
  return @[ @{ NSPrintPanelAccessorySummaryItemNameKey: @"blackAndWhite",
               NSPrintPanelAccessorySummaryItemDescriptionKey: @"Should the document print only in black and white?" } ];
}

- (void)awakeFromNib {
  [[NSUserDefaults standardUserDefaults] registerDefaults:@{ kBlackAndWhiteKey: @YES } ];
  self.blackAndWhite = [[NSUserDefaults standardUserDefaults] boolForKey:kBlackAndWhiteKey];
  [super awakeFromNib];
}

- (NSSet<NSString *> *)keyPathsForValuesAffectingPreview {
  return [NSSet setWithObject:@"blackAndWhite"];
}

- (void)setBlackAndWhite:(BOOL)blackAndWhite {
  [[NSUserDefaults standardUserDefaults] setBool:blackAndWhite forKey:kBlackAndWhiteKey];
  _blackAndWhite = blackAndWhite;
  if (self.userDidChangeSetting) {
    self.userDidChangeSetting();
  }
}

@end
