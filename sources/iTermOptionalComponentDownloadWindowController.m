//
//  iTermOptionalComponentDownloadWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/27/18.
//

#import "iTermOptionalComponentDownloadWindowController.h"

#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@import Sparkle;

const int iTermMinimumPythonEnvironmentVersion = 18;

@protocol iTermOptionalComponentDownloadPhaseDelegate<NSObject>
- (void)optionalComponentDownloadPhaseDidComplete:(iTermOptionalComponentDownloadPhase *)sender;
- (void)optionalComponentDownloadPhase:(iTermOptionalComponentDownloadPhase *)sender
                    didProgressToBytes:(double)bytesWritten
                               ofTotal:(double)totalBytes;
@end

@interface iTermOptionalComponentDownloadPhase()<NSURLSessionDownloadDelegate>
@property (nonatomic, weak) id<iTermOptionalComponentDownloadPhaseDelegate> delegate;
@property (atomic) BOOL downloading;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, strong) NSURLSession *urlSession;
@end

@implementation iTermOptionalComponentDownloadPhase

- (instancetype)initWithURL:(NSURL *)url
                      title:(NSString *)title
           nextPhaseFactory:(iTermOptionalComponentDownloadPhase *(^)(iTermOptionalComponentDownloadPhase *))nextPhaseFactory {
    self = [super init];
    if (self) {
        _url = [url copy];
        _title = [title copy];
        _nextPhaseFactory = [nextPhaseFactory copy];
    }
    return self;
}

- (void)download {
    assert(!_urlSession);
    assert(!_task);

    self.downloading = YES;
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    _urlSession = [NSURLSession sessionWithConfiguration:sessionConfig
                                                delegate:self
                                           delegateQueue:nil];
    _task = [_urlSession downloadTaskWithURL:_url];
    [_task resume];
}

- (void)cancel {
    const BOOL wasDownloading = self.downloading;
    self.downloading = NO;
    [_task cancel];
    _urlSession = nil;
    _task = nil;
    if (wasDownloading) {
        // -999 is the magic number meaning canceled
        _error = [NSError errorWithDomain:@"com.iterm2" code:-999 userInfo:nil];
        [self.delegate optionalComponentDownloadPhaseDidComplete:self];
    }
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.downloading) {
            // Was not canceled
            [self.delegate optionalComponentDownloadPhase:self didProgressToBytes:totalBytesWritten ofTotal:downloadTask.countOfBytesExpectedToReceive];
        }
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    _stream = [NSInputStream inputStreamWithURL:location];
    [_stream open];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
    if (!error) {
        int statusCode = [[NSHTTPURLResponse castFrom:task.response] statusCode];
        if (statusCode != 200) {
            error = [NSError errorWithDomain:@"com.iterm2" code:1 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server returned status code %@: %@", @(statusCode), [NSHTTPURLResponse localizedStringForStatusCode:statusCode] ] }];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.downloading) {
            // Was canceled
            return;
        }
        self.downloading = NO;
        self->_urlSession = nil;
        self->_task = nil;
        self->_error = error;
        [self.delegate optionalComponentDownloadPhaseDidComplete:self];
    });
}

@end

@implementation iTermManifestDownloadPhase

- (instancetype)initWithURL:(NSURL *)url
           nextPhaseFactory:(iTermOptionalComponentDownloadPhase *(^)(iTermOptionalComponentDownloadPhase *))nextPhaseFactory {
    return [super initWithURL:url title:@"Finding latest version…" nextPhaseFactory:nextPhaseFactory];
}

- (BOOL)iTermVersionAtLeast:(NSString *)minVersion
                     atMost:(NSString *)maxVersion {
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (!version) {
        return NO;
    }
    if ([version containsString:@".git."]) {
        // Assume it's the top of master because there's no ordering on git commit numbers
        return YES;
    }
    id<SUVersionComparison> comparator = [SUStandardVersionComparator defaultComparator];
    NSComparisonResult result;
    if (minVersion) {
        result = [comparator compareVersion:version toVersion:minVersion];
        if (result == NSOrderedAscending) {
            return NO;
        }
    }

    if (maxVersion) {
        result = [comparator compareVersion:version toVersion:maxVersion];
        if (result == NSOrderedDescending) {
            return NO;
        }
    }

    return YES;
}

- (NSDictionary *)parsedManifestFromInputStream:(NSInputStream *)stream {
    id obj = [NSJSONSerialization JSONObjectWithStream:stream options:0 error:nil];
    NSArray *array = [NSArray castFrom:obj];
    if (array) {
        int bestVersion = -1;
        NSDictionary *bestDict = nil;
        for (id element in array) {
            NSDictionary *dict = [NSDictionary castFrom:element];
            if (!dict) {
                continue;
            }
            if (dict[@"url"] && dict[@"signature"] && dict[@"version"]) {
                int version = [dict[@"version"] intValue];
                if (version > bestVersion) {
                    NSString *minimumTermVersion = dict[@"minimum_iterm_version"];
                    NSString *maximumTermVersion = dict[@"maximum_iterm_version"];
                    if ([self iTermVersionAtLeast:minimumTermVersion atMost:maximumTermVersion]) {
                        bestVersion = version;
                        bestDict = dict;
                    }
                }
            }
        }
        return bestDict;
    }

    // Deprecated. OK to delete after June 2018
    NSDictionary *dict = [NSDictionary castFrom:obj];
    if (dict[@"url"] && dict[@"signature"] && dict[@"version"]) {
        return dict;
    } else {
        return nil;
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
    if (!error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *dict = [self parsedManifestFromInputStream:self.stream];
            NSError *innerError = nil;
            const int version = [dict[@"version"] intValue];
            if (version < iTermMinimumPythonEnvironmentVersion) {
                innerError = [NSError errorWithDomain:@"com.iterm2" code:3 userInfo:@{ NSLocalizedDescriptionKey: @"☹️ No usable version found." }];
            } else if (dict) {
                self->_nextURL = [NSURL URLWithString:dict[@"url"]];
                self->_signature = dict[@"signature"];
                self->_version = version;
            } else {
                innerError = [NSError errorWithDomain:@"com.iterm2" code:2 userInfo:@{ NSLocalizedDescriptionKey: @"☹️ Malformed manifest." }];
            }
            [super URLSession:session task:task didCompleteWithError:innerError];
        });
    } else {
        [super URLSession:session task:task didCompleteWithError:error];
    }
}

@end

@implementation iTermPayloadDownloadPhase

- (instancetype)initWithURL:(NSURL *)url expectedSignature:(NSString *)expectedSignature {
    self = [super initWithURL:url title:@"Downloading Python runtime…" nextPhaseFactory:nil];
    if (self) {
        _expectedSignature = [expectedSignature copy];
    }
    return self;
}

@end

@interface iTermOptionalComponentDownloadWindowController ()<iTermOptionalComponentDownloadPhaseDelegate>

@end

@implementation iTermOptionalComponentDownloadWindowController {
    IBOutlet NSTextField *_titleLabel;
    IBOutlet NSTextField *_progressLabel;
    IBOutlet NSProgressIndicator *_progressIndicator;
    IBOutlet NSButton *_button;
    iTermOptionalComponentDownloadPhase *_firstPhase;
    BOOL _showingMessage;
}

- (void)windowDidLoad {
    [super windowDidLoad];

    _titleLabel.stringValue = @"Initializing…";
    _progressLabel.stringValue = [NSString stringWithFormat:@""];
}

- (void)beginPhase:(iTermOptionalComponentDownloadPhase *)phase {
    _showingMessage = NO;
    assert(!_currentPhase.downloading);
    if (!_currentPhase) {
        _firstPhase = phase;
    }
    _currentPhase = phase;
    _titleLabel.stringValue = phase.title;
    phase.delegate = self;
    [phase download];
    _progressLabel.stringValue = [NSString stringWithFormat:@"Connecting…"];
    _button.enabled = YES;
    _button.title = @"Cancel";
}

- (void)showMessage:(NSString *)message {
    _showingMessage = YES;
    _titleLabel.stringValue = message;
    _progressLabel.stringValue = @"";
    _button.enabled = YES;
    _button.title = @"OK";
}

- (IBAction)button:(id)sender {
    if (_showingMessage) {
        [self.window close];
    } else if (_currentPhase.downloading) {
        [_currentPhase cancel];
    } else {
        [self beginPhase:_firstPhase];
    }
}

- (void)downloadDidFailWithError:(NSError *)error {
    _button.enabled = YES;
    _button.title = @"Try Again";
    if (error.code == -999) {
        _progressLabel.stringValue = @"Canceled";
        _titleLabel.stringValue = @"";
    } else {
        _progressLabel.stringValue = @"";
        _titleLabel.stringValue = error.localizedDescription;
    }
    _progressIndicator.doubleValue = 0;
    iTermOptionalComponentDownloadPhase *phase = _currentPhase;
    _currentPhase = nil;
    self.completion(phase);
}

#pragma mark - iTermOptionalComponentDownloadPhaseDelegate

- (void)optionalComponentDownloadPhaseDidComplete:(iTermOptionalComponentDownloadPhase *)sender {
    if (sender.error) {
        [self downloadDidFailWithError:sender.error];
    } else if (sender.nextPhaseFactory) {
        iTermOptionalComponentDownloadPhase *nextPhase = sender.nextPhaseFactory(_currentPhase);
        if (nextPhase) {
            [self beginPhase:nextPhase];
        } else {
            iTermOptionalComponentDownloadPhase *phase = _currentPhase;
            _currentPhase = nil;
            self.completion(phase);
        }
    } else {
        _button.enabled = NO;
        _progressLabel.stringValue = @"Finished";
        iTermOptionalComponentDownloadPhase *phase = _currentPhase;
        _currentPhase = nil;
        self.completion(phase);
    }
}

- (void)optionalComponentDownloadPhase:(iTermOptionalComponentDownloadPhase *)sender
                    didProgressToBytes:(double)bytesWritten
                               ofTotal:(double)totalBytes {
    self->_progressIndicator.doubleValue = bytesWritten / totalBytes;
    self->_progressLabel.stringValue = [NSString stringWithFormat:@"%@ of %@",
                                        [NSString it_formatBytes:bytesWritten],
                                        [NSString it_formatBytes:totalBytes]];
}

@end
