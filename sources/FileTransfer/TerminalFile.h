//
//  TerminalFile.h
//  iTerm
//
//  Created by George Nachman on 1/5/14.
//
//

#import "TransferrableFile.h"

// Posted when the transfer wants to stop.
extern NSString *const kTerminalFileShouldStopNotification;

// A file downloaded from the terminal via an escape code.
@interface TerminalFile : TransferrableFile

@property(nonatomic, copy) NSString *localPath;
@property(nonatomic, readonly) NSInteger length;

// You must call -download after initWithName:size: to enter starting status.
// A nil name opens a save panel.
// A size of -1 means the size is unknown.
- (instancetype)initWithName:(NSString *)name size:(NSInteger)size;

// Appends data to a file in transferring status. Enters transferring status.
// Returns NO if the transfer should be aborted.
- (BOOL)appendData:(NSString *)data;

// Marks the end of data, at which time the file is decoded and saved. If -stop
// was called, the cancelled state is entered.
- (void)endOfData;

@end

@interface TerminalFileDownload : TerminalFile
@property (nonatomic) BOOL preconfirmed;
@end

@interface TerminalFileUpload : TerminalFile
- (void)didUploadBytes:(NSInteger)count;
@end
