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

NSArray<NSString *> *SIGArchiveGetKnownKeys(void);

long long SIGAddNonnegativeInt64s(long long a, long long b);
