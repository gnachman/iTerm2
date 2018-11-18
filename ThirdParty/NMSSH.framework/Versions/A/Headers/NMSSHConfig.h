#import "NMSSH.h"

@class NMSSHHostConfig;

/**
 NMSSHConfig parses ssh config files and returns matching entries for a given
 host name.
 */
@interface NMSSHConfig : NSObject

/** The array of parsed NMSSHHostConfig objects. */
@property (nonatomic, nonnull, readonly) NSArray<NMSSHHostConfig *> *hostConfigs;

/**
 Creates a new NMSSHConfig, reads the given {filename} and parses it.

 @param filename Path to an ssh config file.
 @returns NMSSHConfig instance or nil if the config file couldn't be parsed.
 */
+ (nullable instancetype)configFromFile:(nonnull NSString *)filename;

/**
 Initializes an NMSSHConfig from a config file's contents in a string.

 @param contents A config file's contents.
 @returns An NMSSHConfig object or nil if the contents were malformed.
 */
- (nullable instancetype)initWithString:(nonnull NSString *)contents;

/**
 Searches the config for an entry matching {host}.

 @param host A host name to search for.
 @returns An NMSSHHostConfig object whose patterns match host or nil if none is
     found.
 */
- (nullable NMSSHHostConfig *)hostConfigForHost:(nonnull NSString *)host;

@end
