//
//  ProfileTableRow.m
//  iTerm
//
//  Created by George Nachman on 1/9/12.
//

#import "ProfileTableRow.h"
#import "ITAddressBookMgr.h"

@implementation ProfileTableRow {
    NSString* guid;
    ProfileModel* underlyingModel;
}

- (instancetype)initWithBookmark:(Profile*)bookmark
                 underlyingModel:(ProfileModel*)newUnderlyingModel {
    self = [super init];
    if (self) {
        guid = [[bookmark objectForKey:KEY_GUID] retain];
        self->underlyingModel = [newUnderlyingModel retain];
    }
    return self;
}

- (void)dealloc
{
    [underlyingModel release];
    [guid release];
    [super dealloc];
}

- (Profile*)bookmark
{
    return [underlyingModel bookmarkWithGuid:guid];
}

@end

@implementation ProfileTableRow (KeyValueCoding)

- (NSNumber*)default
{
    BOOL isDefault = [[[self bookmark] objectForKey:KEY_GUID] isEqualToString:[[[ProfileModel sharedInstance] defaultBookmark] objectForKey:KEY_GUID]];
    return [NSNumber numberWithInt:isDefault ? IsDefault : IsNotDefault];
}

- (NSString*)name
{
    return [[self bookmark] objectForKey:KEY_NAME];
}

- (NSString*)shortcut
{
    return [[self bookmark] objectForKey:KEY_SHORTCUT];
}

- (NSString*)command
{
    return [[self bookmark] objectForKey:KEY_COMMAND_LINE];
}

- (NSString*)guid
{
    return [[self bookmark] objectForKey:KEY_GUID];
}

@end

