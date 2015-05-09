//
//  iTermPromotionalMessageManager.m
//  iTerm
//
//  Created by George Nachman on 5/7/15.
//
//

#import "iTermPromotionalMessageManager.h"

// Gently let the user know about upcoming releases that break backward compatibility.
@interface iTermPromotionalMessageManager ()<NSURLDownloadDelegate>
@property(nonatomic, retain) NSMutableData *data;
@property(nonatomic, copy) NSString *downloadFilename;
@end

#define TEST_PROMOS 1

@implementation iTermPromotionalMessageManager {
    NSURLDownload *_download;
    NSArray *_promotion;
    BOOL _scheduled;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (!NSClassFromString(@"NSJSONSerialization")) {
        // This class is needed and is only available on 10.7. We're not going to promo anything
        // with an earlier deployment target anyway.
        return nil;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DisablePromotions"]) {
        return nil;
    }
    self = [super init];
    if (self) {
#if TEST_PROMOS
        const NSTimeInterval delay = 1;
#else
        const NSTimeInterval delay = 3600 * 24;
#endif
        [self performSelector:@selector(beginDownload) withObject:nil afterDelay:delay];
    }
    return self;
}

- (void)dealloc {
    [_data release];
    [_downloadFilename release];
    [_download release];
    [super dealloc];
}

- (void)beginDownload {
    // Try again in a week.
#if TEST_PROMOS
    const NSTimeInterval delay = 1;
#else
    const NSTimeInterval delay = 3600 * 24 * 7;
#endif
    [self performSelector:@selector(beginDownload) withObject:nil afterDelay:delay];

    if (_download) {
        // Still downloading (shouldn't happen).
        return;
    }

    _download = [[NSURLDownload alloc] initWithRequest:[self request] delegate:self];
}

- (NSURLRequest *)request {
    NSURL *url = [NSURL URLWithString:@"https://iterm2.com/appcasts/promo.json"];
    NSMutableURLRequest *request =
    [NSMutableURLRequest requestWithURL:url
                            cachePolicy:NSURLRequestReloadIgnoringCacheData
                        timeoutInterval:30.0];
    self.data = [NSMutableData data];
    return request;
}

static NSString *kPromotionsKey = @"promotions";
static NSString *kPromoIdKey = @"id";
static NSString *kPromoTitleKey = @"title";
static NSString *kPromoMessageKey = @"message";
static NSString *kPromoUrlKey = @"url";
static NSString *kPromoExpirationKey = @"expiration";
static NSString *kPromoMinItermVersionKey = @"min_iterm_version";
static NSString *kPromoMaxItermVersionKey = @"max_iterm_version";
static NSString *const kTimeOfLastPromoKey = @"NoSyncTimeOfLastPromo";

- (NSString *)keyForPromoId:(NSString *)promoId {
    NSString *theKey = [NSString stringWithFormat:@"NoSyncHaveShownPromoWithId_%@", promoId];
    return theKey;
}

- (BOOL)haveShownPromoWithId:(NSString *)promoId {
    NSString *theKey = [self keyForPromoId:promoId];
    return [[NSUserDefaults standardUserDefaults] boolForKey:theKey];
}

- (void)setHaveShownPromoWithId:(NSString *)promoId {
    NSString *theKey = [self keyForPromoId:promoId];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:theKey];
    [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate]
                                              forKey:kTimeOfLastPromoKey];
}

- (NSTimeInterval)timeSinceLastPromo {
    NSTimeInterval lastShown = [[NSUserDefaults standardUserDefaults] doubleForKey:kTimeOfLastPromoKey];
    return [NSDate timeIntervalSinceReferenceDate] - lastShown;
}

- (void)setPromotionFromDictionary:(NSDictionary *)promo {
    NSString *message = promo[kPromoMessageKey];
    NSString *title = promo[kPromoTitleKey];
    NSString *urlString = promo[kPromoUrlKey];
    NSURL *url = [NSURL URLWithString:urlString];
    if (title && message && url) {
        [_promotion autorelease];
        _promotion = [@[ promo[kPromoIdKey], message, title, url ] retain];
    }
}

- (void)showPromotion {
    if (_promotion.count == 4) {
        NSString *promoId = _promotion[0];
        NSString *title = _promotion[1];
        NSString *message = _promotion[2];
        NSURL *url = _promotion[3];
        [self setHaveShownPromoWithId:promoId];
        NSAlert *alert = [NSAlert alertWithMessageText:title
                                         defaultButton:@"Learn More"
                                       alternateButton:@"Dismiss"
                                           otherButton:nil
                             informativeTextWithFormat:@"%@", message];
        if ([alert runModal] == NSAlertDefaultReturn) {
            [[NSWorkspace sharedWorkspace] openURL:url];
        }
        [_promotion autorelease];
        _promotion = nil;
    }
    _scheduled = NO;
}

- (BOOL)promotionIsEligible:(NSDictionary *)promo {
    NSTimeInterval expiration = [promo[kPromoExpirationKey] doubleValue];
    if (expiration) {
        if (expiration < [NSDate timeIntervalSinceReferenceDate]) {
            return NO;
        }
    }
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *minVersion = promo[kPromoMinItermVersionKey];
    if (minVersion) {
        if ([minVersion compare:version] == NSOrderedDescending) {
            return NO;
        }
    }

    NSString *maxVersion = promo[kPromoMaxItermVersionKey];
    if (maxVersion) {
        if ([maxVersion compare:version] == NSOrderedAscending) {
            return NO;
        }
    }

    return YES;
}

- (void)handlePromoDictionary:(NSDictionary *)root {
    NSArray *promotions = root[kPromotionsKey];
    for (NSDictionary *promo in promotions) {
#if TEST_PROMOS
        const NSTimeInterval minTime = 1;
#else
        const NSTimeInterval minTime = 3600 * 24 * 9;
#endif
        if (![self haveShownPromoWithId:promo[kPromoIdKey]] &&
            [self timeSinceLastPromo] > minTime &&
            [self promotionIsEligible:promo]) {
            [self setPromotionFromDictionary:promo];
            break;
        }
    }
}

#pragma mark - NSURLDownloadDelegate

- (void)download:(NSURLDownload *)aDownload decideDestinationWithSuggestedFilename:(NSString *)filename {
    NSString *destinationFilename = NSTemporaryDirectory();
    if (destinationFilename) {
        destinationFilename = [destinationFilename stringByAppendingPathComponent:filename];
        [aDownload setDestination:destinationFilename allowOverwrite:NO];
    }
}

- (void)download:(NSURLDownload *)aDownload didCreateDestination:(NSString *)path {
    self.downloadFilename = path;
}

- (void)downloadDidFinish:(NSURLDownload *)aDownload {
    if (self.downloadFilename) {
        NSData *data = [NSData dataWithContentsOfFile:self.downloadFilename];
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadFilename error:nil];
        self.downloadFilename = nil;
        if (!data) {
            return;
        }
        NSError *error = nil;
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error && !object) {
            NSLog(@"JSON deserialization error: %@", error);
            return;
        } else if ([object isKindOfClass:[NSDictionary class]]) {
            NSDictionary *root = object;
            [self handlePromoDictionary:root];
        } else {
            NSLog(@"Unexpected class for JSON root: %@", [object class]);
        }
    }
    [_download release];
    _download = nil;
}

- (void)download:(NSURLDownload *)aDownload didFailWithError:(NSError *)error {
    if (self.downloadFilename) {
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadFilename error:nil];
    }
    self.downloadFilename = nil;
    [_download release];
    _download = nil;

    NSLog(@"Download of promo json failed.");
}

- (NSURLRequest *)download:(NSURLDownload *)aDownload
           willSendRequest:(NSURLRequest *)request
          redirectResponse:(NSURLResponse *)redirectResponse {
    return request;
}

- (void)scheduleDisplayIfNeeded {
    if (_scheduled || !_promotion) {
        return;
    }
    _scheduled = YES;
    [self performSelector:@selector(showPromotion) withObject:nil afterDelay:5];
}

@end

