//
//  iTermPromotionalMessageManager.m
//  iTerm
//
//  Created by George Nachman on 5/7/15.
//
//

#import "iTermPromotionalMessageManager.h"
#import "iTermApplicationDelegate.h"
#import "NSStringITerm.h"

static NSString *kPromotionsKey = @"promotions";
static NSString *kPromoIdKey = @"id";
static NSString *kPromoTitleKey = @"title";
static NSString *kPromoMessageKey = @"message";
static NSString *kPromoUrlKey = @"url";
static NSString *kPromoExpirationKey = @"expiration";
static NSString *kPromoMinItermVersionKey = @"min_iterm_version";
static NSString *kPromoMaxItermVersionKey = @"max_iterm_version";
static NSString *const kTimeOfLastPromoKey = @"NoSyncTimeOfLastPromo";
static NSString *const kPromotionsDisabledKey = @"NoSyncDisablePromotions";
static NSString *const kTimeOfLastPromoDownloadKey = @"NoSyncTimeOfLastPromoDownload";

static NSTimeInterval kMinTimeBetweenDownloads = 3600 * 24;  // 24 hours

// Gently let the user know about upcoming releases that break backward compatibility.
@interface iTermPromotionalMessageManager ()<NSURLDownloadDelegate>
@property(nonatomic, retain) NSMutableData *data;
@property(nonatomic, copy) NSString *downloadFilename;
@property(nonatomic, retain) NSURLResponse *response;
@end

//#define TEST_PROMOS 1

@implementation iTermPromotionalMessageManager {
    NSURLDownload *_download;
    NSArray *_promotion;  // An array of [ promoId, message, title, url ]
    BOOL _scheduled;
    NSMutableData *_data;
    NSString *_downloadFilename;
    NSURLResponse *_response;
}

@synthesize data = _data;
@synthesize downloadFilename = _downloadFilename;
@synthesize response = _response;

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    DLog(@"Initialize promo manager");
    if (!NSClassFromString(@"NSJSONSerialization")) {
        DLog(@"JSON serialization not available, abort.");
        // This class is needed and is only available on 10.7. We're not going to promo anything
        // with an earlier deployment target anyway.
        return nil;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kPromotionsDisabledKey]) {
        DLog(@"Promos disabled");
        return nil;
    }
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"SUEnableAutomaticChecks"]) {
        DLog(@"Auto update disabled");
        return nil;
    }
    self = [super init];
    if (self) {
        // If there's no value for kTimeOfLastPromoKey set it to "now" to avoid showing a promo
        // immediately after the first run of a new install.
        if (![[NSUserDefaults standardUserDefaults] objectForKey:kTimeOfLastPromoKey]) {
            DLog(@"Initialize last promo time to now because not set");
            [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate]
                                                      forKey:kTimeOfLastPromoKey];
        }
        [self beginDownload];
    }
    return self;
}

- (void)dealloc {
    [_data release];
    [_downloadFilename release];
    [_download release];
    [_response release];
    [super dealloc];
}

- (void)beginDownload {
#if TEST_PROMOS
    const NSTimeInterval delay = 1;
#else
    // Try again in a day.
    const NSTimeInterval delay = kMinTimeBetweenDownloads;
#endif

    NSTimeInterval lastDownload =
        [[NSUserDefaults standardUserDefaults] doubleForKey:kTimeOfLastPromoDownloadKey];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval elapsedTime = now - lastDownload;
    if (elapsedTime < delay) {
        DLog(@"Schedule promo download for %f sec from now", (delay - elapsedTime + 1));
        // Did a download in the last 24 hours. Schedule another attempt at the right time.
        // Add an extra second to avoid any possible edge case.
        [self performSelector:@selector(beginDownload)
                   withObject:nil
                   afterDelay:delay - elapsedTime + 1];

        return;
    } else {
        // Schedule another download in 24 hours.
        DLog(@"Schedule next download for %f seconds from now", delay);
        [self performSelector:@selector(beginDownload) withObject:nil afterDelay:delay];
    }
    DLog(@"Update time of last promo download to %f", now);
    [[NSUserDefaults standardUserDefaults] setDouble:now forKey:kTimeOfLastPromoDownloadKey];

    if (_download) {
        DLog(@"Still downloading (this shouldn't happen)");
        // Still downloading (shouldn't happen).
        return;
    }

    NSURLRequest *request = [self request];
    if (request) {
        DLog(@"Create download.");
        _download = [[NSURLDownload alloc] initWithRequest:[self request] delegate:self];
    }
}

- (NSURLRequest *)request {
    NSString *baseUrl = @"https://iterm2.com/appcasts/promo.json";
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *encodedVersion = [version stringWithPercentEscape];
    NSString *urlString = [NSString stringWithFormat:@"%@?v=%@", baseUrl, encodedVersion];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        DLog(@"%@ is not a valid url!", urlString);
        return nil;
    }
    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url
                                cachePolicy:NSURLRequestReloadIgnoringCacheData
                            timeoutInterval:30.0];
    self.data = [NSMutableData data];
    return request;
}

- (NSString *)keyForPromoId:(NSString *)promoId {
    NSString *theKey = [NSString stringWithFormat:@"NoSyncHaveShownPromoWithId_%@", promoId];
    DLog(@"Key for promo id %@ is %@", promoId, theKey);
    return theKey;
}

- (BOOL)haveShownPromoWithId:(NSString *)promoId {
    NSString *theKey = [self keyForPromoId:promoId];
    BOOL result = [[NSUserDefaults standardUserDefaults] boolForKey:theKey];
    DLog(@"have shown promo: %@", @(result));
    return result;
}

- (void)setHaveShownPromoWithId:(NSString *)promoId {
    DLog(@"Set have shown promo %@", promoId);
    NSString *theKey = [self keyForPromoId:promoId];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:theKey];
    [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate]
                                              forKey:kTimeOfLastPromoKey];
}

- (NSTimeInterval)timeSinceLastPromo {
    NSTimeInterval lastShown =
        [[NSUserDefaults standardUserDefaults] doubleForKey:kTimeOfLastPromoKey];
    NSTimeInterval result = [NSDate timeIntervalSinceReferenceDate] - lastShown;
    DLog(@"Time since last promo is %f", result);
    return result;
}

- (void)setPromotionFromDictionary:(NSDictionary *)promo {
    DLog(@"Set promo from dict %@", promo);

    NSString *promoId = promo[kPromoIdKey];
    NSString *message = promo[kPromoMessageKey];
    NSString *title = promo[kPromoTitleKey];
    NSString *urlString = promo[kPromoUrlKey];
    NSURL *url = [NSURL URLWithString:urlString];
    [_promotion autorelease];
    if (promoId && title && message && url) {
        _promotion = [@[ promoId, message, title, url ] retain];
    } else {
        _promotion = nil;
    }
    DLog(@"Set promo to %@", _promotion);
}

- (void)showPromotion {
    DLog(@"showPromotion");
    if (_promotion.count == 4) {
        DLog(@"Promo is valid, here we go");
        NSString *promoId = _promotion[0];
        NSString *title = _promotion[1];
        NSString *message = _promotion[2];
        NSURL *url = _promotion[3];
        [self setHaveShownPromoWithId:promoId];
        [_promotion autorelease];
        _promotion = nil;

        NSAlert *alert = [NSAlert alertWithMessageText:title
                                         defaultButton:@"Learn More"
                                       alternateButton:@"Dismiss"
                                           otherButton:nil
                             informativeTextWithFormat:@"%@", message];
        alert.suppressionButton.title = @"Do not show promotions for new versions of iTerm2 again.";
        alert.showsSuppressionButton = YES;

        if ([alert runModal] == NSAlertDefaultReturn) {
            DLog(@"Open url %@", url);
            [[NSWorkspace sharedWorkspace] openURL:url];
        }
        if (alert.suppressionButton.state == NSOnState) {
            DLog(@"Suppress");
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPromotionsDisabledKey];
        }
    }
    DLog(@"Set scheduled=NO");
    _scheduled = NO;
}

- (BOOL)promotionIsEligible:(NSDictionary *)promo {
    NSTimeInterval expiration = [promo[kPromoExpirationKey] doubleValue];
    if (expiration) {
        if (expiration < [NSDate timeIntervalSinceReferenceDate]) {
            DLog(@"Promo ineligible because expiration is %f", expiration);
            return NO;
        }
    }
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *minVersion = promo[kPromoMinItermVersionKey];
    if (minVersion) {
        if ([minVersion compare:version] == NSOrderedDescending) {
            DLog(@"Promo ineligible because minVersion is %@ but my version is %@",
                 minVersion, version);
            return NO;
        }
    }

    NSString *maxVersion = promo[kPromoMaxItermVersionKey];
    if (maxVersion) {
        if ([maxVersion compare:version] == NSOrderedAscending) {
            DLog(@"Promo ineligible because maxVersion is %@ but my version is %@",
                 maxVersion, version);
            return NO;
        }
    }

    DLog(@"Promo eligible");
    return YES;
}

- (void)loadPromoFromDictionaryIfEligible:(NSDictionary *)root {
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

            DLog(@"Promo is ok, load it up.");
            [self setPromotionFromDictionary:promo];
            break;
        }
    }
}

#pragma mark - NSURLDownloadDelegate

- (void)download:(NSURLDownload *)aDownload decideDestinationWithSuggestedFilename:(NSString *)filename {
    DLog(@"Download decide destination with suggested filename %@", filename);
    NSString *destinationFilename = NSTemporaryDirectory();
    if (destinationFilename) {
        destinationFilename = [destinationFilename stringByAppendingPathComponent:filename];
        DLog(@"Destination filename is %@", destinationFilename);
        [aDownload setDestination:destinationFilename allowOverwrite:NO];
    }
}

- (void)download:(NSURLDownload *)aDownload didCreateDestination:(NSString *)path {
    DLog(@"did create %@", path);
    self.downloadFilename = path;
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response {
    DLog(@"set response to %@", response);
    self.response = response;
}

- (void)downloadDidFinish:(NSURLDownload *)aDownload {
    DLog(@"Download did finish");
    if (self.downloadFilename) {
        DLog(@"Have filename %@", self.downloadFilename);
        NSData *data = [NSData dataWithContentsOfFile:self.downloadFilename];
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadFilename error:nil];
        self.downloadFilename = nil;
        if (!data) {
            DLog(@"No data");
            return;
        }

        if (![_response isKindOfClass:[NSHTTPURLResponse class]]) {
            DLog(@"Response class is %@", _response.class);
            return;
        }
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)_response;
        if (httpResponse.statusCode != 200) {
            DLog(@"Status code is %@", @(httpResponse.statusCode));
            return;
        }
        NSError *error = nil;
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error && !object) {
            DLog(@"JSON deserialization error: %@", error);
            return;
        } else if ([object isKindOfClass:[NSDictionary class]]) {
            DLog(@"Download got a dictionary from json");
            NSDictionary *root = object;
            [self loadPromoFromDictionaryIfEligible:root];
        } else {
            DLog(@"Unexpected class for JSON root: %@", [object class]);
        }
    }
    DLog(@"Nil out download");
    [_download release];
    _download = nil;
}

- (void)download:(NSURLDownload *)aDownload didFailWithError:(NSError *)error {
    DLog(@"Download failed: %@", error);
    if (self.downloadFilename) {
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadFilename error:nil];
    }
    self.downloadFilename = nil;
    [_download release];
    _download = nil;
}

- (NSURLRequest *)download:(NSURLDownload *)aDownload
           willSendRequest:(NSURLRequest *)request
          redirectResponse:(NSURLResponse *)redirectResponse {
    DLog(@"Download will send request");
    return request;
}

- (void)scheduleDisplayIfNeeded {
    DLog(@"Schedule display if needed...");
    if (_scheduled || !_promotion) {
        DLog(@"Not needed. scheduled=%@", @(_scheduled));
        return;
    }
    DLog(@"Call showPromotion in 5 seconds");
    _scheduled = YES;
    [self performSelector:@selector(showPromotion) withObject:nil afterDelay:5];
}

@end

