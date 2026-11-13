/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */
#ifndef INCLUDE_sys_git_config_backend_h__
#define INCLUDE_sys_git_config_backend_h__

#include "git2/common.h"
#include "git2/types.h"
#include "git2/config.h"

/**
 * @file git2/sys/config.h
 * @brief Custom configuration database backends
 * @defgroup git_backend Custom configuration database backends
 * @ingroup Git
 * @{
 */
GIT_BEGIN_DECL

/**
 * An entry in a configuration backend. This is provided so that
 * backend implementors can have a mechanism to free their data.
 */
typedef struct git_config_backend_entry {
	/** The base configuration entry */
	struct git_config_entry entry;

	/**
	 * Free function for this entry; for internal purposes. Callers
	 * should call `git_config_entry_free` to free data.
	 */
	void GIT_CALLBACK(free)(struct git_config_backend_entry *entry);
} git_config_backend_entry;

/**
 * Every iterator must have this struct as its first element, so the
 * API can talk to it. You'd define your iterator as
 *
 *     struct my_iterator {
 *             git_config_iterator parent;
 *             ...
 *     }
 *
 * and assign `iter->parent.backend` to your `git_config_backend`.
 */
struct git_config_iterator {
	git_config_backend *backend;
	unsigned int flags;

	/**
	 * Return the current entry and advance the iterator. The
	 * memory belongs to the library.
	 */
	int GIT_CALLBACK(next)(git_config_backend_entry **entry, git_config_iterator *iter);

	/**
	 * Free the iterator
	 */
	void GIT_CALLBACK(free)(git_config_iterator *iter);
};

/**
 * Generic backend that implements the interface to
 * access a configuration file
 */
struct git_config_backend {
	unsigned int version;
	/** True if this backend is for a snapshot */
	int readonly;
	struct git_config *cfg;

	/* Open means open the file/database and parse if necessary */
	int GIT_CALLBACK(open)(struct git_config_backend *, git_config_level_t level, const git_repository *repo);
	int GIT_CALLBACK(get)(struct git_config_backend *, const char *key, git_config_backend_entry **entry);
	int GIT_CALLBACK(set)(struct git_config_backend *, const char *key, const char *value);
	int GIT_CALLBACK(set_multivar)(git_config_backend *cfg, const char *name, const char *regexp, const char *value);
	int GIT_CALLBACK(del)(struct git_config_backend *, const char *key);
	int GIT_CALLBACK(del_multivar)(struct git_config_backend *, const char *key, const char *regexp);
	int GIT_CALLBACK(iterator)(git_config_iterator **, struct git_config_backend *);
	/** Produce a read-only version of this backend */
	int GIT_CALLBACK(snapshot)(struct git_config_backend **, struct git_config_backend *);
	/**
	 * Lock this backend.
	 *
	 * Prevent any writes to the data store backing this
	 * backend. Any updates must not be visible to any other
	 * readers.
	 */
	int GIT_CALLBACK(lock)(struct git_config_backend *);
	/**
	 * Unlock the data store backing this backend. If success is
	 * true, the changes should be committed, otherwise rolled
	 * back.
	 */
	int GIT_CALLBACK(unlock)(struct git_config_backend *, int success);
	void GIT_CALLBACK(free)(struct git_config_backend *);
};

/** Current version for the `git_config_backend_options` structure */
#define GIT_CONFIG_BACKEND_VERSION 1

/** Static constructor for `git_config_backend_options` */
#define GIT_CONFIG_BACKEND_INIT {GIT_CONFIG_BACKEND_VERSION}

/**
 * Initializes a `git_config_backend` with default values. Equivalent to
 * creating an instance with GIT_CONFIG_BACKEND_INIT.
 *
 * @param backend the `git_config_backend` struct to initialize.
 * @param version Version of struct; pass `GIT_CONFIG_BACKEND_VERSION`
 * @return Zero on success; -1 on failure.
 */
GIT_EXTERN(int) git_config_init_backend(
	git_config_backend *backend,
	unsigned int version);

/**
 * Add a generic config file instance to an existing config
 *
 * Note that the configuration object will free the file
 * automatically.
 *
 * Further queries on this config object will access each
 * of the config file instances in order (instances with
 * a higher priority level will be accessed first).
 *
 * @param cfg the configuration to add the file to
 * @param file the configuration file (backend) to add
 * @param level the priority level of the backend
 * @param repo optional repository to allow parsing of
 *  conditional includes
 * @param force if a config file already exists for the given
 *  priority level, replace it
 * @return 0 on success, GIT_EEXISTS when adding more than one file
 *  for a given priority level (and force_replace set to 0), or error code
 */
GIT_EXTERN(int) git_config_add_backend(
	git_config *cfg,
	git_config_backend *file,
	git_config_level_t level,
	const git_repository *repo,
	int force);

/** Options for in-memory configuration backends. */
typedef struct {
	unsigned int version;

	/**
	 * The type of this backend (eg, "command line"). If this is
	 * NULL, then this will be "in-memory".
	 */
	const char *backend_type;

	/**
	 * The path to the origin; if this is NULL then it will be
	 * left unset in the resulting configuration entries.
	 */
	const char *origin_path;
} git_config_backend_memory_options;

/** Current version for the `git_config_backend_memory_options` structure */
#define GIT_CONFIG_BACKEND_MEMORY_OPTIONS_VERSION 1

/** Static constructor for `git_config_backend_memory_options` */
#define GIT_CONFIG_BACKEND_MEMORY_OPTIONS_INIT { GIT_CONFIG_BACKEND_MEMORY_OPTIONS_VERSION }


/**
 * Create an in-memory configuration backend from a string in standard
 * git configuration file format.
 *
 * @param out the new backend
 * @param cfg the configuration that is to be parsed
 * @param len the length of the string pointed to by `cfg`
 * @param opts the options to initialize this backend with, or NULL
 * @return 0 on success or an error code
 */
extern int git_config_backend_from_string(
	git_config_backend **out,
	const char *cfg,
	size_t len,
	git_config_backend_memory_options *opts);

/**
 * Create an in-memory configuration backend from a list of name/value
 * pairs.
 *
 * @param out the new backend
 * @param values the configuration values to set (in "key=value" format)
 * @param len the length of the values array
 * @param opts the options to initialize this backend with, or NULL
 * @return 0 on success or an error code
 */
extern int git_config_backend_from_values(
	git_config_backend **out,
	const char **values,
	size_t len,
	git_config_backend_memory_options *opts);

/** @} */
GIT_END_DECL

#endif
