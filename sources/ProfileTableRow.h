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
{
    NSString* guid;
    ProfileModel* underlyingModel;
}

- (instancetype)initWithBookmark:(Profile*)bookmark underlyingModel:(ProfileModel*)underlyingModel;
- (Profile*)bookmark;

@end

@interface ProfileTableRow (KeyValueCoding)
// We need ascending order to sort default before not-default so we can't use
// anything senible like BOOL or "Yes"/"No" because they'd sort wrong.
typedef enum { IsDefault = 1, IsNotDefault = 2 } BookmarkRowIsDefault;
- (NSNumber*)default;
- (NSString*)name;
- (NSString*)shortcut;
- (NSString*)command;
- (NSString*)guid;
@end

