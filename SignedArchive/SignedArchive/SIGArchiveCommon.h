#import <Foundation/Foundation.h>

// Create archives readable by older versions?
#define ENABLE_SIGARCHIVE_MIGRATION_CREATION 0

// Accept archives from older versions?
#define ENABLE_SIGARCHIVE_MIGRATION_VALIDATION 0

#if ENABLE_SIGARCHIVE_MIGRATION_CREATION || ENABLE_SIGARCHIVE_MIGRATION_VALIDATION
#warning NOTE: SIGArchive migration flags enabled
#endif

extern NSString *const SIGArchiveDigestTypeSHA2;

extern NSString *const SIGArchiveMetadataKeyVersion;
extern NSString *const SIGArchiveMetadataKeyDigestType;

// Present only in encrypted archives. See SIGArchiveEncryption.h.
extern NSString *const SIGArchiveMetadataKeyEncryption;
extern NSString *const SIGArchiveMetadataKeyKDF;
extern NSString *const SIGArchiveMetadataKeyKDFIterations;
extern NSString *const SIGArchiveMetadataKeyKDFSalt;

NSArray<NSString *> *SIGArchiveGetKnownKeys(void);

// Parses the metadata chunk's key=value lines. Unknown keys are ignored. Returns nil and sets
// *error if a known key is repeated.
NSDictionary<NSString *, NSString *> *SIGArchiveParseMetadata(NSString *metadata, NSError **error);

long long SIGAddNonnegativeInt64s(long long a, long long b);
