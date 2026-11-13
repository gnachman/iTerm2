/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */
#ifndef INCLUDE_git_common_h__
#define INCLUDE_git_common_h__

#include <time.h>
#include <stdlib.h>

#ifdef __cplusplus
 /** Start declarations in C mode for C++ compatibility */
# define GIT_BEGIN_DECL extern "C" {
 /** End declarations in C mode */
# define GIT_END_DECL	}
#else
 /** Start declarations in C mode */
# define GIT_BEGIN_DECL /* empty */
 /** End declarations in C mode */
# define GIT_END_DECL	/* empty */
#endif

#if defined(_MSC_VER) && _MSC_VER < 1800
# include <stdint.h>
#elif !defined(__CLANG_INTTYPES_H)
# include <inttypes.h>
#endif

#ifdef DOCURIUM
/*
 * This is so clang's doc parser acknowledges comments on functions
 * with size_t parameters.
 */
typedef size_t size_t;
#endif

/** Declare a public function exported for application use. */
#if __GNUC__ >= 4
# define GIT_EXTERN(type) extern \
			 __attribute__((visibility("default"))) \
			 type
#elif defined(_MSC_VER)
# define GIT_EXTERN(type) __declspec(dllexport) type __cdecl
#else
# define GIT_EXTERN(type) extern type
#endif

/** Declare a callback function for application use. */
#if defined(_MSC_VER)
# define GIT_CALLBACK(name) (__cdecl *name)
#else
# define GIT_CALLBACK(name) (*name)
#endif

/** Declare a function as deprecated. */
#if defined(__GNUC__)
# define GIT_DEPRECATED(func) \
			 __attribute__((deprecated)) \
			 __attribute__((used)) \
			 func
#elif defined(_MSC_VER)
# define GIT_DEPRECATED(func) __declspec(deprecated) func
#else
# define GIT_DEPRECATED(func) func
#endif

/** Declare a function's takes printf style arguments. */
#ifdef __GNUC__
# define GIT_FORMAT_PRINTF(a,b) __attribute__((format (printf, a, b)))
#else
# define GIT_FORMAT_PRINTF(a,b) /* empty */
#endif

#ifdef __amigaos4__
#include <netinet/in.h>
#endif

/**
 * @file git2/common.h
 * @brief Base platform functionality
 * @defgroup git_common Git common platform definitions
 * @ingroup Git
 *
 * Common platform functionality including introspecting libgit2
 * itself - information like how it was built, and the current
 * running version.
 * @{
 */

GIT_BEGIN_DECL

/**
 * The separator used in path list strings (ie like in the PATH
 * environment variable). A semi-colon ";" is used on Windows and
 * AmigaOS, and a colon ":" for all other systems.
 */
#if (defined(_WIN32) && !defined(__CYGWIN__)) || defined(AMIGA)
# define GIT_PATH_LIST_SEPARATOR ';'
#else
# define GIT_PATH_LIST_SEPARATOR ':'
#endif

/**
 * The maximum length of a valid git path.
 */
#define GIT_PATH_MAX 4096

/**
 * Return the version of the libgit2 library
 * being currently used.
 *
 * @param major Store the major version number
 * @param minor Store the minor version number
 * @param rev Store the revision (patch) number
 * @return 0 on success or an error code on failure
 */
GIT_EXTERN(int) git_libgit2_version(int *major, int *minor, int *rev);

/**
 * Return the prerelease state of the libgit2 library currently being
 * used.  For nightly builds during active development, this will be
 * "alpha".  Releases may have a "beta" or release candidate ("rc1",
 * "rc2", etc) prerelease.  For a final release, this function returns
 * NULL.
 *
 * @return the name of the prerelease state or NULL
 */
GIT_EXTERN(const char *) git_libgit2_prerelease(void);

/**
 * Configurable features of libgit2; either optional settings (like
 * threading), or features that can be enabled by one of a number of
 * different backend "providers" (like HTTPS, which can be provided by
 * OpenSSL, mbedTLS, or system libraries).
 */
typedef enum {
	/**
	 * libgit2 is thread-aware and can be used from multiple threads
	 * (as described in the documentation).
	 */
	GIT_FEATURE_THREADS        = (1 << 0),

	/** HTTPS remotes */
	GIT_FEATURE_HTTPS          = (1 << 1),

	/** SSH remotes */
	GIT_FEATURE_SSH	           = (1 << 2),

	/** Sub-second resolution in index timestamps */
	GIT_FEATURE_NSEC           = (1 << 3),

	/** HTTP parsing; always available */
	GIT_FEATURE_HTTP_PARSER    = (1 << 4),

	/** Regular expression support; always available */
	GIT_FEATURE_REGEX          = (1 << 5),

	/** Internationalization support for filename translation */
	GIT_FEATURE_I18N           = (1 << 6),

	/** NTLM support over HTTPS */
	GIT_FEATURE_AUTH_NTLM      = (1 << 7),

	/** Kerberos (SPNEGO) authentication support over HTTPS */
	GIT_FEATURE_AUTH_NEGOTIATE = (1 << 8),

	/** zlib support; always available */
	GIT_FEATURE_COMPRESSION    = (1 << 9),

	/** SHA1 object support; always available */
	GIT_FEATURE_SHA1           = (1 << 10),

	/** SHA256 object support */
	GIT_FEATURE_SHA256         = (1 << 11)
} git_feature_t;

/**
 * Query compile time options for libgit2.
 *
 * @return A combination of GIT_FEATURE_* values.
 */
GIT_EXTERN(int) git_libgit2_features(void);

/**
 * Query the backend details for the compile-time feature in libgit2.
 *
 * This will return the "backend" for the feature, which is useful for
 * things like HTTPS or SSH support, that can have multiple backends
 * that could be compiled in.
 *
 * For example, when libgit2 is compiled with dynamic OpenSSL support,
 * the feature backend will be `openssl-dynamic`. The feature backend
 * names reflect the compilation options specified to the build system
 * (though in all lower case). The backend _may_ be "builtin" for
 * features that are provided by libgit2 itself.
 *
 * If the feature is not supported by the library, this API returns
 * `NULL`.
 *
 * @param feature the feature to query details for
 * @return the provider details, or NULL if the feature is not supported
 */
GIT_EXTERN(const char *) git_libgit2_feature_backend(
	git_feature_t feature);

/**
 * Global library options
 *
 * These are used to select which global option to set or get and are
 * used in `git_libgit2_opts()`.
 */
typedef enum {
	GIT_OPT_GET_MWINDOW_SIZE,
	GIT_OPT_SET_MWINDOW_SIZE,
	GIT_OPT_GET_MWINDOW_MAPPED_LIMIT,
	GIT_OPT_SET_MWINDOW_MAPPED_LIMIT,
	GIT_OPT_GET_SEARCH_PATH,
	GIT_OPT_SET_SEARCH_PATH,
	GIT_OPT_SET_CACHE_OBJECT_LIMIT,
	GIT_OPT_SET_CACHE_MAX_SIZE,
	GIT_OPT_ENABLE_CACHING,
	GIT_OPT_GET_CACHED_MEMORY,
	GIT_OPT_GET_TEMPLATE_PATH,
	GIT_OPT_SET_TEMPLATE_PATH,
	GIT_OPT_SET_SSL_CERT_LOCATIONS,
	GIT_OPT_SET_USER_AGENT,
	GIT_OPT_ENABLE_STRICT_OBJECT_CREATION,
	GIT_OPT_ENABLE_STRICT_SYMBOLIC_REF_CREATION,
	GIT_OPT_SET_SSL_CIPHERS,
	GIT_OPT_GET_USER_AGENT,
	GIT_OPT_ENABLE_OFS_DELTA,
	GIT_OPT_ENABLE_FSYNC_GITDIR,
	GIT_OPT_GET_WINDOWS_SHAREMODE,
	GIT_OPT_SET_WINDOWS_SHAREMODE,
	GIT_OPT_ENABLE_STRICT_HASH_VERIFICATION,
	GIT_OPT_SET_ALLOCATOR,
	GIT_OPT_ENABLE_UNSAVED_INDEX_SAFETY,
	GIT_OPT_GET_PACK_MAX_OBJECTS,
	GIT_OPT_SET_PACK_MAX_OBJECTS,
	GIT_OPT_DISABLE_PACK_KEEP_FILE_CHECKS,
	GIT_OPT_ENABLE_HTTP_EXPECT_CONTINUE,
	GIT_OPT_GET_MWINDOW_FILE_LIMIT,
	GIT_OPT_SET_MWINDOW_FILE_LIMIT,
	GIT_OPT_SET_ODB_PACKED_PRIORITY,
	GIT_OPT_SET_ODB_LOOSE_PRIORITY,
	GIT_OPT_GET_EXTENSIONS,
	GIT_OPT_SET_EXTENSIONS,
	GIT_OPT_GET_OWNER_VALIDATION,
	GIT_OPT_SET_OWNER_VALIDATION,
	GIT_OPT_GET_HOMEDIR,
	GIT_OPT_SET_HOMEDIR,
	GIT_OPT_SET_SERVER_CONNECT_TIMEOUT,
	GIT_OPT_GET_SERVER_CONNECT_TIMEOUT,
	GIT_OPT_SET_SERVER_TIMEOUT,
	GIT_OPT_GET_SERVER_TIMEOUT,
	GIT_OPT_SET_USER_AGENT_PRODUCT,
	GIT_OPT_GET_USER_AGENT_PRODUCT,
	GIT_OPT_ADD_SSL_X509_CERT,
	GIT_OPT_GET_PACK_MAX_OBJECT_SIZE,
	GIT_OPT_SET_PACK_MAX_OBJECT_SIZE
} git_libgit2_opt_t;

/**
 * Set or query a library global option
 *
 * Available options:
 *
 *	* opts(GIT_OPT_GET_MWINDOW_SIZE, size_t *):
 *
 *		> Get the maximum mmap window size
 *
 *	* opts(GIT_OPT_SET_MWINDOW_SIZE, size_t):
 *
 *		> Set the maximum mmap window size
 *
 *	* opts(GIT_OPT_GET_MWINDOW_MAPPED_LIMIT, size_t *):
 *
 *		> Get the maximum memory that will be mapped in total by the library
 *
 *	* opts(GIT_OPT_SET_MWINDOW_MAPPED_LIMIT, size_t):
 *
 *		> Set the maximum amount of memory that can be mapped at any time
 *		> by the library
 *
 *	* opts(GIT_OPT_GET_MWINDOW_FILE_LIMIT, size_t *):
 *
 *		> Get the maximum number of files that will be mapped at any time by the
 *		> library
 *
 *	* opts(GIT_OPT_SET_MWINDOW_FILE_LIMIT, size_t):
 *
 *		> Set the maximum number of files that can be mapped at any time
 *		> by the library. The default (0) is unlimited.
 *
 *	* opts(GIT_OPT_GET_SEARCH_PATH, int level, git_buf *buf)
 *
 *		> Get the search path for a given level of config data.  "level" must
 *		> be one of `GIT_CONFIG_LEVEL_SYSTEM`, `GIT_CONFIG_LEVEL_GLOBAL`,
 *		> `GIT_CONFIG_LEVEL_XDG`, or `GIT_CONFIG_LEVEL_PROGRAMDATA`.
 *		> The search path is written to the `out` buffer.
 *
 *	* opts(GIT_OPT_SET_SEARCH_PATH, int level, const char *path)
 *
 *		> Set the search path for a level of config data.  The search path
 *		> applied to shared attributes and ignore files, too.
 *		>
 *		> - `path` lists directories delimited by GIT_PATH_LIST_SEPARATOR.
 *		>   Pass NULL to reset to the default (generally based on environment
 *		>   variables).  Use magic path `$PATH` to include the old value
 *		>   of the path (if you want to prepend or append, for instance).
 *		>
 *		> - `level` must be `GIT_CONFIG_LEVEL_SYSTEM`,
 *		>   `GIT_CONFIG_LEVEL_GLOBAL`, `GIT_CONFIG_LEVEL_XDG`, or
 *		>   `GIT_CONFIG_LEVEL_PROGRAMDATA`.
 *
 *	* opts(GIT_OPT_SET_CACHE_OBJECT_LIMIT, git_object_t type, size_t size)
 *
 *		> Set the maximum data size for the given type of object to be
 *		> considered eligible for caching in memory.  Setting to value to
 *		> zero means that that type of object will not be cached.
 *		> Defaults to 0 for GIT_OBJECT_BLOB (i.e. won't cache blobs) and 4k
 *		> for GIT_OBJECT_COMMIT, GIT_OBJECT_TREE, and GIT_OBJECT_TAG.
 *
 *	* opts(GIT_OPT_SET_CACHE_MAX_SIZE, ssize_t max_storage_bytes)
 *
 *		> Set the maximum total data size that will be cached in memory
 *		> across all repositories before libgit2 starts evicting objects
 *		> from the cache.  This is a soft limit, in that the library might
 *		> briefly exceed it, but will start aggressively evicting objects
 *		> from cache when that happens.  The default cache size is 256MB.
 *
 *	* opts(GIT_OPT_ENABLE_CACHING, int enabled)
 *
 *		> Enable or disable caching completely.
 *		>
 *		> Because caches are repository-specific, disabling the cache
 *		> cannot immediately clear all cached objects, but each cache will
 *		> be cleared on the next attempt to update anything in it.
 *
 *	* opts(GIT_OPT_GET_CACHED_MEMORY, ssize_t *current, ssize_t *allowed)
 *
 *		> Get the current bytes in cache and the maximum that would be
 *		> allowed in the cache.
 *
 *	* opts(GIT_OPT_GET_TEMPLATE_PATH, git_buf *out)
 *
 *		> Get the default template path.
 *		> The path is written to the `out` buffer.
 *
 *	* opts(GIT_OPT_SET_TEMPLATE_PATH, const char *path)
 *
 *		> Set the default template path.
 *		>
 *		> - `path` directory of template.
 *
 *	* opts(GIT_OPT_SET_SSL_CERT_LOCATIONS, const char *file, const char *path)
 *
 *		> Set the SSL certificate-authority locations.
 *		>
 *		> - `file` is the location of a file containing several
 *		>   certificates concatenated together.
 *		> - `path` is the location of a directory holding several
 *		>   certificates, one per file.
 *		>
 *		> Calling `GIT_OPT_ADD_SSL_X509_CERT` may override the
 *		> data in `path`.
 *		>
 * 		> Either parameter may be `NULL`, but not both.
 *
 *  * opts(GIT_OPT_ADD_SSL_X509_CERT, const X509 *cert)
 *
 *		> Add a raw X509 certificate into the SSL certs store.
 *		> This certificate is only used by libgit2 invocations
 *		> during the application lifetime and is not persisted
 *		> to disk. This certificate cannot be removed from the
 *		> application once is has been added.
 *		>
 *		> - `cert` is the raw X509 cert will be added to cert store.
 *
 *	* opts(GIT_OPT_SET_USER_AGENT, const char *user_agent)
 *
 *		> Set the value of the comment section of the User-Agent header.
 *		> This can be information about your product and its version.
 *		> By default this is "libgit2" followed by the libgit2 version.
 *		>
 *		> This value will be appended to User-Agent _product_, which
 *		> is typically set to "git/2.0".
 *		>
 *		> Set to the empty string ("") to not send any information in the
 *		> comment section, or set to NULL to restore the default.
 *
 *	* opts(GIT_OPT_GET_USER_AGENT, git_buf *out)
 *
 *		> Get the value of the User-Agent header.
 *		> The User-Agent is written to the `out` buffer.
 *
 *	* opts(GIT_OPT_SET_USER_AGENT_PRODUCT, const char *user_agent_product)
 *
 *		> Set the value of the product portion of the User-Agent header.
 *		> This defaults to "git/2.0", for compatibility with other git
 *		> clients. It is recommended to keep this as git/<version> for
 *		> compatibility with servers that do user-agent detection.
 *		>
 *		> Set to the empty string ("") to not send any user-agent string,
 *		> or set to NULL to restore the default.
 *
 *	* opts(GIT_OPT_GET_USER_AGENT_PRODUCT, git_buf *out)
 *
 *		> Get the value of the User-Agent product header.
 *		> The User-Agent product is written to the `out` buffer.
 *
 *	* opts(GIT_OPT_SET_WINDOWS_SHAREMODE, unsigned long value)
 *
 *		> Set the share mode used when opening files on Windows.
 *		> For more information, see the documentation for CreateFile.
 *		> The default is: FILE_SHARE_READ | FILE_SHARE_WRITE.  This is
 *		> ignored and unused on non-Windows platforms.
 *
 *	* opts(GIT_OPT_GET_WINDOWS_SHAREMODE, unsigned long *value)
 *
 *		> Get the share mode used when opening files on Windows.
 *
 *	* opts(GIT_OPT_ENABLE_STRICT_OBJECT_CREATION, int enabled)
 *
 *		> Enable strict input validation when creating new objects
 *		> to ensure that all inputs to the new objects are valid.  For
 *		> example, when this is enabled, the parent(s) and tree inputs
 *		> will be validated when creating a new commit.  This defaults
 *		> to enabled.
 *
 *	* opts(GIT_OPT_ENABLE_STRICT_SYMBOLIC_REF_CREATION, int enabled)
 *
 *		> Validate the target of a symbolic ref when creating it.  For
 *		> example, `foobar` is not a valid ref, therefore `foobar` is
 *		> not a valid target for a symbolic ref by default, whereas
 *		> `refs/heads/foobar` is.  Disabling this bypasses validation
 *		> so that an arbitrary strings such as `foobar` can be used
 *		> for a symbolic ref target.  This defaults to enabled.
 *
 *	* opts(GIT_OPT_SET_SSL_CIPHERS, const char *ciphers)
 *
 *		> Set the SSL ciphers use for HTTPS connections.
 *		>
 *		> - `ciphers` is the list of ciphers that are eanbled.
 *
 *	* opts(GIT_OPT_ENABLE_OFS_DELTA, int enabled)
 *
 *		> Enable or disable the use of "offset deltas" when creating packfiles,
 *		> and the negotiation of them when talking to a remote server.
 *		> Offset deltas store a delta base location as an offset into the
 *		> packfile from the current location, which provides a shorter encoding
 *		> and thus smaller resultant packfiles.
 *		> Packfiles containing offset deltas can still be read.
 *		> This defaults to enabled.
 *
 *	* opts(GIT_OPT_ENABLE_FSYNC_GITDIR, int enabled)
 *
 *		> Enable synchronized writes of files in the gitdir using `fsync`
 *		> (or the platform equivalent) to ensure that new object data
 *		> is written to permanent storage, not simply cached.  This
 *		> defaults to disabled.
 *
 *	 opts(GIT_OPT_ENABLE_STRICT_HASH_VERIFICATION, int enabled)
 *
 *		> Enable strict verification of object hashsums when reading
 *		> objects from disk. This may impact performance due to an
 *		> additional checksum calculation on each object. This defaults
 *		> to enabled.
 *
 *	 opts(GIT_OPT_SET_ALLOCATOR, git_allocator *allocator)
 *
 *		> Set the memory allocator to a different memory allocator. This
 *		> allocator will then be used to make all memory allocations for
 *		> libgit2 operations.  If the given `allocator` is NULL, then the
 *		> system default will be restored.
 *
 *	 opts(GIT_OPT_ENABLE_UNSAVED_INDEX_SAFETY, int enabled)
 *
 *		> Ensure that there are no unsaved changes in the index before
 *		> beginning any operation that reloads the index from disk (eg,
 *		> checkout).  If there are unsaved changes, the instruction will
 *		> fail.  (Using the FORCE flag to checkout will still overwrite
 *		> these changes.)
 *
 *	 opts(GIT_OPT_GET_PACK_MAX_OBJECTS, size_t *out)
 *
 *		> Get the maximum number of objects libgit2 will allow in a pack
 *		> file when downloading a pack file from a remote. This can be
 *		> used to limit maximum memory usage when fetching from an untrusted
 *		> remote.
 *
 *	 opts(GIT_OPT_SET_PACK_MAX_OBJECTS, size_t objects)
 *
 *		> Set the maximum number of objects libgit2 will allow in a pack
 *		> file when downloading a pack file from a remote.
 *
 *	 opts(GIT_OPT_DISABLE_PACK_KEEP_FILE_CHECKS, int enabled)
 *		> This will cause .keep file existence checks to be skipped when
 *		> accessing packfiles, which can help performance with remote filesystems.
 *
 *	 opts(GIT_OPT_ENABLE_HTTP_EXPECT_CONTINUE, int enabled)
 *		> When connecting to a server using NTLM or Negotiate
 *		> authentication, use expect/continue when POSTing data.
 *		> This option is not available on Windows.
 *
 *   opts(GIT_OPT_SET_ODB_PACKED_PRIORITY, int priority)
 *      > Override the default priority of the packed ODB backend which
 *      > is added when default backends are assigned to a repository
 *
 *   opts(GIT_OPT_SET_ODB_LOOSE_PRIORITY, int priority)
 *      > Override the default priority of the loose ODB backend which
 *      > is added when default backends are assigned to a repository
 *
 *   opts(GIT_OPT_GET_EXTENSIONS, git_strarray *out)
 *      > Returns the list of git extensions that are supported.  This
 *      > is the list of built-in extensions supported by libgit2 and
 *      > custom extensions that have been added with
 *      > `GIT_OPT_SET_EXTENSIONS`.  Extensions that have been negated
 *      > will not be returned.  The returned list should be released
 *      > with `git_strarray_dispose`.
 *
 *   opts(GIT_OPT_SET_EXTENSIONS, const char **extensions, size_t len)
 *      > Set that the given git extensions are supported by the caller.
 *      > Extensions supported by libgit2 may be negated by prefixing
 *      > them with a `!`.  For example: setting extensions to
 *      > { "!noop", "newext" } indicates that the caller does not want
 *      > to support repositories with the `noop` extension but does want
 *      > to support repositories with the `newext` extension.
 *
 *   opts(GIT_OPT_GET_OWNER_VALIDATION, int *enabled)
 *      > Gets the owner validation setting for repository
 *      > directories.
 *
 *   opts(GIT_OPT_SET_OWNER_VALIDATION, int enabled)
 *      > Set that repository directories should be owned by the current
 *      > user. The default is to validate ownership.
 *
 *   opts(GIT_OPT_GET_HOMEDIR, git_buf *out)
 *      > Gets the current user's home directory, as it will be used
 *      > for file lookups. The path is written to the `out` buffer.
 *
 *   opts(GIT_OPT_SET_HOMEDIR, const char *path)
 *      > Sets the directory used as the current user's home directory,
 *      > for file lookups.
 *      >
 *      > - `path` directory of home directory.
 *
 *   opts(GIT_OPT_GET_SERVER_CONNECT_TIMEOUT, int *timeout)
 *      > Gets the timeout (in milliseconds) to attempt connections to
 *      > a remote server.
 *
 *   opts(GIT_OPT_SET_SERVER_CONNECT_TIMEOUT, int timeout)
 *      > Sets the timeout (in milliseconds) to attempt connections to
 *      > a remote server. Set to 0 to use the system default. Note that
 *      > this may not be able to be configured longer than the system
 *      > default, typically 75 seconds.
 *
 *   opts(GIT_OPT_GET_SERVER_TIMEOUT, int *timeout)
 *      > Gets the timeout (in milliseconds) for reading from and writing
 *      > to a remote server.
 *
 *   opts(GIT_OPT_SET_SERVER_TIMEOUT, int timeout)
 *      > Sets the timeout (in milliseconds) for reading from and writing
 *      > to a remote server. Set to 0 to use the system default.
 *
 *   opts(GIT_OPT_GET_PACK_MAX_OBJECT_SIZE, size_t *out)
 *      > Gets the maximum size of a declared packfile object. This can
 *      > be used to limit maximum memory usage when fetching from a
 *      > remote.
 *
 *   opts(GIT_OPT_SET_PACK_MAX_OBJECT_SIZE, size_t object_size)
 *      > Set the maximum size of an object that libgit2 will allow in
 *      > a pack file when downloading a pack file from a remote.
 *      > The default is 2 GiB.
 *
 * @param option Option key
 * @return 0 on success, <0 on failure
 */
GIT_EXTERN(int) git_libgit2_opts(int option, ...);

/** @} */
GIT_END_DECL

#endif
