//
//  iTermCorruptApplicationAlert.h
//  iTerm2
//
//  Shared helper that shows the “Application Corrupt” alert when a required
//  resource is missing or corrupted, and then terminates the process.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Shows a critical modal alert explaining that a required application resource
// is missing or corrupted. The exact wording depends on the app’s code-signature
// state. If settingKey is non-nil, the informative text is wrapped in a message
// describing which setting was being loaded when the problem was detected. This
// function does not return: it calls exit(1) after the alert is dismissed.
void iTermShowCorruptApplicationAlert(NSString * _Nullable settingKey);

NS_ASSUME_NONNULL_END
