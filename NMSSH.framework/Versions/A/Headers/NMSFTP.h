#import "NMSSH.h"

/**
 NMSFTP provides functionality for working with SFTP servers.
 */
@interface NMSFTP : NSObject

/** A valid NMSSHSession instance */
@property (nonatomic, readonly) NMSSHSession *session;

/** Property that keeps track of connection status to the server */
@property (nonatomic, readonly, getter = isConnected) BOOL connected;

///-----------------------------------------------------------------------------
/// @name Initializer
/// ----------------------------------------------------------------------------

/**
 Create a new NMSFTP instance and connect it.

 @param session A valid, connected, NMSSHSession instance
 @returns Connected NMSFTP instance
 */
+ (instancetype)connectWithSession:(NMSSHSession *)session;

/**
 Create a new NMSFTP instance.

 @param session A valid, connected, NMSSHSession instance
 @returns New NMSFTP instance
 */
- (instancetype)initWithSession:(NMSSHSession *)session;

/// ----------------------------------------------------------------------------
/// @name Connection
/// ----------------------------------------------------------------------------

/**
 Create and connect to a SFTP session

 @returns Connection status
 */
- (BOOL)connect;

/**
 Disconnect SFTP session
 */
- (void)disconnect;

/// ----------------------------------------------------------------------------
/// @name Manipulate file system entries
/// ----------------------------------------------------------------------------

/**
 Move or rename an item

 @param sourcePath Item to move
 @param destPath Destination to move to
 @returns Move success
 */
- (BOOL)moveItemAtPath:(NSString *)sourcePath toPath:(NSString *)destPath;

/// ----------------------------------------------------------------------------
/// @name Manipulate directories
/// ----------------------------------------------------------------------------

/**
 Test if a directory exists at the specified path.

 Note: Will return NO if a file exists at the path, but not a directory.

 @param path Path to check
 @returns YES if file exists
 */
- (BOOL)directoryExistsAtPath:(NSString *)path;

/**
 Create a directory at path

 @param path Path to directory
 @returns Creation success
 */
- (BOOL)createDirectoryAtPath:(NSString *)path;

/**
 Remove directory at path

 @param path Existing directory
 @returns Remove success
 */
- (BOOL)removeDirectoryAtPath:(NSString *)path;

/**
 Get a list of file names for a directory path

 @param path Existing directory to list items from
 @returns List of relative paths
 */
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path;

/// ----------------------------------------------------------------------------
/// @name Manipulate symlinks and files
/// ----------------------------------------------------------------------------

/**
 Test if a file exists at the specified path.

 Note: Will return NO if a directory exists at the path, but not a file.

 @param path Path to check
 @returns YES if file exists
 */
- (BOOL)fileExistsAtPath:(NSString *)path;

/**
 Create a symbolic link

 @param linkPath Path that will be linked to
 @param destPath Path the link will be created at
 @returns Creation success
 */
- (BOOL)createSymbolicLinkAtPath:(NSString *)linkPath
             withDestinationPath:(NSString *)destPath;

/**
 Remove file at path

 @param path Path to existing file
 @returns Remove success
 */
- (BOOL)removeFileAtPath:(NSString *)path;

/**
 Read the contents of a file

 @param path An existing file path
 @returns File contents
 */
- (NSData *)contentsAtPath:(NSString *)path;

/**
 Overwrite the contents of a file

 If no file exists, one is created.

 @param contents Bytes to write
 @param path File path to write bytes at
 @returns Write success
 */
- (BOOL)writeContents:(NSData *)contents toFileAtPath:(NSString *)path;

/**
 Overwrite the contents of a file

 If no file exists, one is created.

 @param localPath File path to read bytes at
 @param path File path to write bytes at
 @returns Write success
 */
- (BOOL)writeFileAtPath:(NSString *)localPath toFileAtPath:(NSString *)path;

/**
 Overwrite the contents of a file

 If no file exists, one is created.

 @param inputStream Stream to read bytes from
 @param path File path to write bytes at
 @returns Write success
 */
- (BOOL)writeStream:(NSInputStream *)inputStream toFileAtPath:(NSString *)path;

/**
 Append contents to the end of a file

 If no file exists, one is created.

 @param contents Bytes to write
 @param path File path to write bytes at
 @returns Append success
 */
- (BOOL)appendContents:(NSData *)contents toFileAtPath:(NSString *)path;

/**
 Append contents to the end of a file

 If no file exists, one is created.

 @param inputStream Stream to write bytes from
 @param path File path to write bytes at
 @returns Append success
 */
- (BOOL)appendStream:(NSInputStream *)inputStream toFileAtPath:(NSString *)path;

@end
