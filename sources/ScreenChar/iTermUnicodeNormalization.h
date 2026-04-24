//
//  iTermUnicodeNormalization.h
//  iTerm2
//
//  Unicode normalization modes.
//

#import <Foundation/Foundation.h>

// Do not renumber. These are tag numbers and also saved in prefs.
typedef NS_ENUM(NSUInteger, iTermUnicodeNormalization) {
    iTermUnicodeNormalizationNone = 0,
    iTermUnicodeNormalizationNFC = 1,
    iTermUnicodeNormalizationNFD = 2,
    iTermUnicodeNormalizationHFSPlus = 3,
};
