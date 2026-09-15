//
//  iTermStandardButtons.h
//  iTerm2
//
//  Shared accessors for the standard localized “OK” and “Cancel” button labels.
//  These own the General.OK / General.Cancel localization keys, values, and
//  comments in exactly one place so that call sites do not each duplicate them.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Returns the localized “OK” button label (General.OK).
NSString *iTermLocalizedOK(void);

// Returns the localized “Cancel” button label (General.Cancel).
NSString *iTermLocalizedCancel(void);

// Returns the localized “Copy” button label (General.Copy).
NSString *iTermLocalizedCopy(void);

// Returns the localized “Yes” button label (General.Yes).
NSString *iTermLocalizedYes(void);

// Returns the localized “No” button label (General.No).
NSString *iTermLocalizedNo(void);

// Returns the localized “Add” button label (General.Add).
NSString *iTermLocalizedAdd(void);

// Returns the localized “Remove” button label (General.Remove).
NSString *iTermLocalizedRemove(void);

// Returns the localized “Edit” button label (General.Edit).
NSString *iTermLocalizedEdit(void);

NS_ASSUME_NONNULL_END
