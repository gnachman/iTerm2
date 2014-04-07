//
//  PreferenceInfo.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Cocoa/Cocoa.h>

typedef enum {
    kPreferenceInfoTypeCheckbox,
    kPreferenceInfoTypeIntegerTextField,
    kPreferenceInfoTypeStringTextField,
    kPreferenceInfoTypePopup,
    kPreferenceInfoTypeSlider
} PreferenceInfoType;


@interface PreferenceInfo : NSObject

@property(nonatomic, retain) NSString *key;
@property(nonatomic, assign) PreferenceInfoType type;
@property(nonatomic, retain) NSControl *control;
@property(nonatomic, assign) NSRange range;  // For integer fields, the range of legal values.

// A function that indicates if the control should be enabled. If nil, then the control is always
// enabled.
@property(nonatomic, copy) BOOL (^shouldBeEnabled)();

// Called when value changes with PreferenceInfo as object.
@property(nonatomic, copy) void (^onChange)();

+ (instancetype)infoForPreferenceWithKey:(NSString *)key
                                    type:(PreferenceInfoType)type
                                 control:(NSControl *)control;

@end
