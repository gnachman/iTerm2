/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */
#ifndef INCLUDE_sys_git_repository_h__
#define INCLUDE_sys_git_repository_h__

#include "git2/common.h"
#include "git2/types.h"
#include "git2/oid.h"

/**
 * @file git2/sys/repository.h
 * @brief Custom repository handling
 * @defgroup git_repository Custom repository handling
 * @ingroup Git
 * @{
 */
GIT_BEGIN_DECL

#ifdef GIT_EXPERIMENTAL_SHA256

/**
 * The options for creating an repository from scratch.
 *
 * Initialize with `GIT_REPOSITORY_NEW_OPTIONS_INIT`. Alternatively,
 * you can use `git_repository_new_options_init`.
 *
 * @options[version] GIT_REPOSITORY_NEW_OPTIONS_VERSION
 * @options[init_macro] GIT_REPOSITORY_NEW_OPTIONS_INIT
 * @options[init_function] git_repository_new_options_init
 */
typedef struct git_repository_new_options {
	unsigned int version; /**< The version */

	/**
	 * The object ID type for the object IDs that exist in the index.
	 *
	 * If this is not specified, this defaults to `GIT_OID_SHA1`.
	 */
	git_oid_t oid_type;
} git_repository_new_options;

/** Current version for the `git_repository_new_options` structure */
#define GIT_REPOSITORY_NEW_OPTIONS_VERSION 1

/** Static constructor for `git_repository_new_options` */
#define GIT_REPOSITORY_NEW_OPTIONS_INIT { GIT_REPOSITORY_NEW_OPTIONS_VERSION }

/**
 * Initialize git_repository_new_options structure
 *
 * Initializes a `git_repository_new_options` with default values.
 * Equivalent to creating an instance with
 * `GIT_REPOSITORY_NEW_OPTIONS_INIT`.
 *
 * @param opts The `git_repository_new_options` struct to initialize.
 * @param version The struct version; pass `GIT_REPOSITORY_NEW_OPTIONS_VERSION`.
 * @return Zero on success; -1 on failure.
 */
GIT_EXTERN(int) git_repository_new_options_init(
	git_repository_new_options *opts,
	unsigned int version);

/**
 * Create a new repository with no backends.
 *
 * @param[out] out The blank repository
 * @param opts the options for repository creation, or NULL for defaults
 * @return 0 on success, or an error code
 */
GIT_EXTERN(int) git_repository_new(git_repository **out, git_repository_new_options *opts);
#else

/**
 * Create a new repository with neither backends nor config object
 *
 * Note that this is only useful if you wish to associate the repository
 * with a non-filesystem-backed object database and config store.
 *
 * Caveats: since this repository has no physical location, some systems
 * can fail to function properly: locations under $GIT_DIR, $GIT_COMMON_DIR,
 * or $GIT_INFO_DIR are impacted.
 *
 * @param[out] out The blank repository
 * @return 0 on success, or an error code
 */
GIT_EXTERN(int) git_repository_new(git_repository **out);

#endif

/**
 * Reset all the internal state in a repository.
 *
 * This will free all the mapped memory and internal objects
 * of the repository and leave it in a "blank" state.
 *
 * There's no need to call this function directly unless you're
 * trying to aggressively cleanup the repo before its
 * deallocation. `git_repository_free` already performs this operation
 * before deallocating the repo.
 *
 * @param repo The repository to clean up
 * @return 0 on success, or an error code
 */
GIT_EXTERN(int) git_repository__cleanup(git_repository *repo);

/**
 * Update the filesystem config settings for an open repository
 *
 * When a repository is initialized, config values are set based on the
 * properties of the filesystem that the repository is on, such as
 * "core.ignorecase", "core.filemode", "core.symlinks", etc.  If the
 * repository is moved to a new filesystem, these properties may no
 * longer be correct and API calls may not behave as expected.  This
 * call reruns the phase of repository initialization that sets those
 * properties to compensate for the current filesystem of the repo.
 *
 * @param repo A repository object
 * @param recurse_submodules Should submodules be updated recursively
 * @return 0 on success, < 0 on error
 */
GIT_EXTERN(int) git_repository_reinit_filesystem(
	git_repository *repo,
	int recurse_submodules);

/**
 * Set the configuration file for this repository
 *
 * This configuration file will be used for all configuration
 * queries involving this repository.
 *
 * The repository will keep a reference to the config file;
 * the user must still free the config after setting it
 * to the repository, or it will leak.
 *
 * @param repo A repository object
 * @param config A Config object
 * @return 0 on success, or an error code
 */
GIT_EXTERN(int) git_repository_set_config(git_repository *repo, git_config *config);

/**
 * Set the Object Database for this repository
 *
 * The ODB will be used for all object-related operations
 * involving this repository.
 *
 * The repository will keep a reference to the ODB; the user
 * must still free the ODB object after setting it to the
 * repository, or it will leak.
 *
 * @param repo A repository object
 * @param odb An ODB object
 * @return 0 on success, or an error code
 */
GIT_EXTERN(int) git_repository_set_odb(git_repository *repo, git_odb *odb);

/**
 * Set the Reference Database Backend for this repository
 *
 * The refdb will be used for all reference related operations
 * involving this repository.
 *
 * The repository will keep a reference to the refdb; the user
 * must still free the refdb object after setting it to the
 * repository, or it will leak.
 *
 * @param repo A repository object
 * @param refdb An refdb object
 * @return 0 on success, or an error code
 */
GIT_EXTERN(int) git_repository_set_refdb(git_repository *repo, git_refdb *refdb);

/**
 * Set the index file for this repository
 *
 * This index will be used for all index-related operations
 * involving this repository.
 *
 * The repository will keep a reference to the index file;
 * the user must still free the index after setting it
 * to the repository, or it will leak.
 *
 * @param repo A repository object
 * @param index An index object
 * @return 0 on success, or an error code
 */
GIT_EXTERN(int) git_repository_set_index(git_repository *repo, git_index *index);

/**
 * Set a repository to be bare.
 *
 * Clear the working directory and set core.bare to true.  You may also
 * want to call `git_repository_set_index(repo, NULL)` since a bare repo
 * typically does not have an index, but this function will not do that
 * for you.
 *
 * @param repo Repo to make bare
 * @return 0 on success, <0 on failure
 */
GIT_EXTERN(int) git_repository_set_bare(git_repository *repo);

/**
 * Load and cache all submodules.
 *
 * Because the `.gitmodules` file is unstructured, loading submodules is an
 * O(N) operation.  Any operation (such as `git_rebase_init`) that requires
 * accessing all submodules is O(N^2) in the number of submodules, if it
 * has to look each one up individually.  This function loads all submodules
 * and caches them so that subsequent calls to `git_submodule_lookup` are O(1).
 *
 * @param repo the repository whose submodules will be cached.
 * @return 0 on success, or an error code
 */
GIT_EXTERN(int) git_repository_submodule_cache_all(
	git_repository *repo);

/**
 * Clear the submodule cache.
 *
 * Clear the submodule cache populated by `git_repository_submodule_cache_all`.
 * If there is no cache, do nothing.
 *
 * The cache incorporates data from the repository's configuration, as well
 * as the state of the working tree, the index, and HEAD.  So any time any
 * of these has changed, the cache might become invalid.
 *
 * @param repo the repository whose submodule cache will be cleared
 * @return 0 on success, or an error code
 */
GIT_EXTERN(int) git_repository_submodule_cache_clear(
	git_repository *repo);

/** @} */
GIT_END_DECL

#endif
