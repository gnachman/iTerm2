#import <Cocoa/Cocoa.h>
#import "CPKFavorite.h"

static NSString *const kNSCodingCPKFavoriteNameKey = @"name";
static NSString *const kNSCodingCPKFavoriteColorKey = @"color";
static NSString *const kNSCodingCPKFavoriteIdentifierKey = @"identifier";

NSString *const kCPKFavoriteUTI = @"com.googlecode.iterm2.ColorPicker.Favorite";

@interface CPKFavorite()
@property(nonatomic) NSString *identifier;
@end

@implementation CPKFavorite

+ (instancetype)favoriteWithColor:(NSColor *)color name:(NSString *)name {
    CPKFavorite *favorite = [[CPKFavorite alloc] init];
    favorite.color = color;
    favorite.name = name;
    return favorite;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding; {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        self.name = [aDecoder decodeObjectOfClass:[NSString class]
                                           forKey:kNSCodingCPKFavoriteNameKey];
        self.color = [aDecoder decodeObjectOfClass:[NSColor class]
                                            forKey:kNSCodingCPKFavoriteColorKey];
        self.identifier = [aDecoder decodeObjectOfClass:[NSString class]
                                                 forKey:kNSCodingCPKFavoriteIdentifierKey];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.name forKey:kNSCodingCPKFavoriteNameKey];
    [aCoder encodeObject:self.color forKey:kNSCodingCPKFavoriteColorKey];
    [aCoder encodeObject:self.identifier forKey:kNSCodingCPKFavoriteIdentifierKey];
}

- (NSString *)identifier {
    if (!_identifier) {
        CFUUIDRef uuid = CFUUIDCreate(nil);
        NSString *uuidString = (__bridge NSString *)CFUUIDCreateString(nil, uuid);
        CFRelease(uuid);
        _identifier = uuidString;
    }
    return _identifier;
}

#pragma mark - NSPasteboardWriting

- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard {
    return @[ kCPKFavoriteUTI ];
}

- (id)pasteboardPropertyListForType:(NSString *)type {
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *coder = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [self encodeWithCoder:coder];
    [coder finishEncoding];
    return data;
}

#pragma mark - NSPasteboardReading

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard {
    return @[ kCPKFavoriteUTI ];
}

- (id)initWithPasteboardPropertyList:(id)propertyList ofType:(NSString *)type {
    NSKeyedUnarchiver *coder = [[NSKeyedUnarchiver alloc] initForReadingWithData:propertyList];
    return [self initWithCoder:coder];
}


@end

