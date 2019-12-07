// Create archives readable by older versions?
#define ENABLE_SIGARCHIVE_MIGRATION_CREATION 1

// Accept archives from older versions?
#define ENABLE_SIGARCHIVE_MIGRATION_VALIDATION 1

#if ENABLE_SIGARCHIVE_MIGRATION_CREATION || ENABLE_SIGARCHIVE_MIGRATION_VALIDATION
#warning NOTE: SIGArchive migration flags enabled
#endif

