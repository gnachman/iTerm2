//
//  BookmarkRow.m
//  iTerm
//
//  Created by George Nachman on 1/9/12.
//

#import "BookmarkRow.h"
#import "ITAddressBookMgr.h"

@implementation BookmarkRow

- (id)initWithBookmark:(Bookmark*)bookmark underlyingModel:(BookmarkModel*)newUnderlyingModel;
{
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

- (Bookmark*)bookmark
{
    return [underlyingModel bookmarkWithGuid:guid];
}

@end

@implementation BookmarkRow (KeyValueCoding)

- (NSNumber*)default
{
    BOOL isDefault = [[[self bookmark] objectForKey:KEY_GUID] isEqualToString:[[[BookmarkModel sharedInstance] defaultBookmark] objectForKey:KEY_GUID]];
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
    return [[self bookmark] objectForKey:KEY_COMMAND];
}

- (NSString*)guid
{
    return [[self bookmark] objectForKey:KEY_GUID];
}

@end

