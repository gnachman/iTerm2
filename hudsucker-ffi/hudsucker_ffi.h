#ifndef HUDSUCKER_FFI_H
#define HUDSUCKER_FFI_H

#pragma once

#include <stdint.h>
#include <stdbool.h>

typedef enum HudsuckerError {
  Success = 0,
  InvalidParameter = -1,
  ProxyCreationFailed = -2,
  ProxyStartFailed = -3,
  RuntimeError = -4,
  MemoryError = -5,
} HudsuckerError;

typedef bool (*HudsuckerRequestCallback)(const char *url, const char *method, void *user_data);

typedef struct HudsuckerProxy {
  uint8_t _private[0];
} HudsuckerProxy;

/**
 * Create a new proxy instance
 *
 * # Parameters
 * * `addr` - Address to bind to (e.g., "127.0.0.1:8080")
 * * `ca_cert_pem` - PEM-encoded CA certificate
 * * `ca_key_pem` - PEM-encoded CA private key
 * * `callback` - Callback function for request filtering
 * * `user_data` - User data pointer passed to callback
 * * `proxy_out` - Output parameter for proxy handle
 *
 * # Returns
 * * `HudsuckerError::Success` on success
 * * Error code on failure
 */
enum HudsuckerError hudsucker_create_proxy(const char *addr,
                                           const char *ca_cert_pem,
                                           const char *ca_key_pem,
                                           HudsuckerRequestCallback callback,
                                           void *user_data,
                                           struct HudsuckerProxy **proxy_out);

/**
 * Stop and destroy the proxy
 *
 * # Parameters
 * * `proxy` - Proxy handle from `hudsucker_create_proxy`
 *
 * # Returns
 * * `HudsuckerError::Success` on success
 * * Error code on failure
 */
enum HudsuckerError hudsucker_destroy_proxy(struct HudsuckerProxy *proxy);

/**
 * Get the last error message (not implemented in this basic version)
 */
const char *hudsucker_get_last_error(void);

/**
 * Generate a CA certificate and private key pair
 *
 * # Parameters
 * * `cert_out` - Output buffer for PEM-encoded certificate (caller must free)
 * * `key_out` - Output buffer for PEM-encoded private key (caller must free)
 *
 * # Returns
 * * `HudsuckerError::Success` on success
 * * Error code on failure
 */
enum HudsuckerError hudsucker_generate_ca_cert(char **cert_out, char **key_out);

/**
 * Free a string allocated by this library
 */
void hudsucker_free_string(char *ptr);

/**
 * Add a domain to the certificate bypass list for a proxy with certificate error handling
 *
 * This function validates the provided bypass token and, if valid, adds the domain
 * to the certificate bypass list. The token is consumed (removed) after validation.
 *
 * # Parameters
 * * `proxy` - Proxy handle from `hudsucker_create_proxy_with_cert_errors`
 * * `domain` - Domain to add to bypass list (e.g., "example.com")
 * * `token` - Valid bypass token from certificate error page
 *
 * # Returns
 * * `HudsuckerError::Success` on success
 * * `HudsuckerError::InvalidParameter` if token is invalid or expired
 * * Error code on failure
 */
enum HudsuckerError hudsucker_add_bypassed_domain(struct HudsuckerProxy *proxy,
                                                  const char *domain,
                                                  const char *token);

/**
 * Remove a domain from the certificate bypass list
 *
 * # Parameters
 * * `proxy` - Proxy handle from `hudsucker_create_proxy_with_cert_errors`
 * * `domain` - Domain to remove from bypass list (e.g., "example.com")
 *
 * # Returns
 * * `HudsuckerError::Success` on success
 * * Error code on failure
 */
enum HudsuckerError hudsucker_remove_bypassed_domain(struct HudsuckerProxy *proxy,
                                                     const char *domain);

/**
 * Check if a domain is in the certificate bypass list
 *
 * # Parameters
 * * `proxy` - Proxy handle from `hudsucker_create_proxy_with_cert_errors`
 * * `domain` - Domain to check (e.g., "example.com")
 *
 * # Returns
 * * `1` if domain is bypassed
 * * `0` if domain is not bypassed
 * * Negative error code on failure
 */
int32_t hudsucker_is_domain_bypassed(struct HudsuckerProxy *proxy, const char *domain);

/**
 * Clear all domains from the certificate bypass list
 *
 * # Parameters
 * * `proxy` - Proxy handle from `hudsucker_create_proxy_with_cert_errors`
 *
 * # Returns
 * * `HudsuckerError::Success` on success
 * * Error code on failure
 */
enum HudsuckerError hudsucker_clear_bypassed_domains(struct HudsuckerProxy *proxy);

/**
 * Create a new proxy instance with certificate error handling
 *
 * This function creates a proxy that will intercept certificate validation errors
 * and display custom-branded error pages instead of generic browser errors.
 * The error pages include an option to bypass the certificate error.
 *
 * # How certificate error handling works:
 *
 * 1. When a client connects to a site with a certificate error (expired, self-signed, etc.),
 *    the rustls/native-tls library fails during the TLS handshake
 * 2. This error propagates through hyper as a connection error
 * 3. Our custom handler intercepts this error in the `handle_error` method
 * 4. We parse the error message to identify certificate-specific issues
 * 5. Instead of returning a generic 502 error, we return a custom HTML page
 * 6. The HTML page explains the issue and offers a "Continue Anyway" option
 *
 * # Parameters
 * * `addr` - Address to bind to (e.g., "127.0.0.1:8080")
 * * `ca_cert_pem` - PEM-encoded CA certificate
 * * `ca_key_pem` - PEM-encoded CA private key
 * * `callback` - Callback function for request filtering (ad blocking)
 * * `user_data` - User data pointer passed to callback
 * * `html_template` - Optional HTML template for error pages (can be NULL for default)
 * * `proxy_out` - Output parameter for proxy handle
 *
 * # Returns
 * * `HudsuckerError::Success` on success
 * * Error code on failure
 */
enum HudsuckerError hudsucker_create_proxy_with_cert_errors(const char *addr,
                                                            const char *ca_cert_pem,
                                                            const char *ca_key_pem,
                                                            HudsuckerRequestCallback callback,
                                                            void *user_data,
                                                            const char *html_template,
                                                            struct HudsuckerProxy **proxy_out);

#endif  /* HUDSUCKER_FFI_H */
