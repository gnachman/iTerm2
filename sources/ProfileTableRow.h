//
//  ProfileTablekRow.h
//  iTerm
//
//  Created by George Nachman on 1/9/12.
//

#import <Foundation/Foundation.h>
#import "ProfileModel.h"

// This wraps a single bookmark and adds a KeyValueCoding. To keep things simple
// it will hold only the bookmark's GUID, since bookmark dictionaries themselves
// are evanescent.
//
// It implements a KeyValueCoding so that sort descriptors will work.
@interface ProfileTableRow : NSObject

@property(nonatomic, readonly) Profile *bookmark;

- (instancetype)initWithBookmark:(Profile*)bookmark underlyingModel:(ProfileModel*)underlyingModel;

@end

@interface ProfileTableRow (KeyValueCoding)
// We need ascending order to sort default before not-default so we can't use
// anything sensible like BOOL or "Yes"/"No" because they'd sort wrong.
typedef NS_ENUM(NSInteger, BookmarkRowIsDefault) {
    IsDefault = 1,
    IsNotDefault = 2
};

@property(nonatomic, readonly) NSString *name;
@property(nonatomic, readonly) NSString *shortcut;
@property(nonatomic, readonly) NSString *command;
@property(nonatomic, readonly) NSString *guid;

- (NSNumber *)default;

@end

