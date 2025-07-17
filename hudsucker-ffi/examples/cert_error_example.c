// Example C program demonstrating certificate error handling with hudsucker-ffi
// 
// This example shows how to use the new hudsucker_create_proxy_with_cert_errors
// function to create a proxy that displays custom error pages for certificate issues.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>

// Include the generated header (assumes you've run cbindgen)
// #include "hudsucker_ffi.h"

// Forward declarations (these would normally come from the generated header)
typedef enum {
    HudsuckerError_Success = 0,
    HudsuckerError_InvalidParameter = -1,
    HudsuckerError_ProxyCreationFailed = -2,
    HudsuckerError_ProxyStartFailed = -3,
    HudsuckerError_RuntimeError = -4,
    HudsuckerError_MemoryError = -5,
} HudsuckerError;

typedef struct HudsuckerProxy HudsuckerProxy;

typedef bool (*HudsuckerRequestCallback)(
    const char* url,
    const char* method,
    void* user_data
);

// Function declarations
HudsuckerError hudsucker_generate_ca_cert(char** cert_out, char** key_out);
HudsuckerError hudsucker_create_proxy_with_cert_errors(
    const char* addr,
    const char* ca_cert_pem,
    const char* ca_key_pem,
    HudsuckerRequestCallback callback,
    void* user_data,
    HudsuckerProxy** proxy_out
);
HudsuckerError hudsucker_destroy_proxy(HudsuckerProxy* proxy);
void hudsucker_free_string(char* ptr);

// Simple ad blocker callback
// This demonstrates the integration - your ad blocking logic still works
// alongside the certificate error handling
bool ad_blocker_callback(const char* url, const char* method, void* user_data) {
    // Simple ad blocking: block requests to known ad domains
    const char* ad_domains[] = {
        "googleads.g.doubleclick.net",
        "googlesyndication.com",
        "google-analytics.com",
        "facebook.com/tr",
        NULL
    };
    
    for (int i = 0; ad_domains[i] != NULL; i++) {
        if (strstr(url, ad_domains[i]) != NULL) {
            printf("🚫 Blocked ad request: %s\n", url);
            return false;  // Block this request
        }
    }
    
    printf("✅ Allowed request: %s\n", url);
    return true;  // Allow this request
}

// Global proxy handle for cleanup
static HudsuckerProxy* g_proxy = NULL;

// Signal handler for clean shutdown
void signal_handler(int signum) {
    printf("\nShutting down proxy...\n");
    if (g_proxy) {
        hudsucker_destroy_proxy(g_proxy);
        g_proxy = NULL;
    }
    exit(0);
}

int main() {
    printf("🔐 Certificate Error Handling Example\n");
    printf("=====================================\n\n");
    
    // Set up signal handler
    signal(SIGINT, signal_handler);
    
    // Generate CA certificate
    char* ca_cert = NULL;
    char* ca_key = NULL;
    
    printf("Generating CA certificate...\n");
    HudsuckerError err = hudsucker_generate_ca_cert(&ca_cert, &ca_key);
    if (err != HudsuckerError_Success) {
        printf("❌ Failed to generate CA certificate: %d\n", err);
        return 1;
    }
    
    printf("✅ CA certificate generated successfully\n");
    
    // Create proxy with certificate error handling
    printf("Creating proxy with certificate error handling...\n");
    
    const char* listen_addr = "127.0.0.1:8080";
    err = hudsucker_create_proxy_with_cert_errors(
        listen_addr,
        ca_cert,
        ca_key,
        ad_blocker_callback,
        NULL,  // user_data
        &g_proxy
    );
    
    if (err != HudsuckerError_Success) {
        printf("❌ Failed to create proxy: %d\n", err);
        hudsucker_free_string(ca_cert);
        hudsucker_free_string(ca_key);
        return 1;
    }
    
    printf("✅ Proxy created successfully\n");
    printf("🌐 Proxy listening on http://%s\n", listen_addr);
    
    // Clean up certificate strings
    hudsucker_free_string(ca_cert);
    hudsucker_free_string(ca_key);
    
    printf("\n");
    printf("📋 Configuration Instructions:\n");
    printf("1. Install the generated CA certificate in your browser/system\n");
    printf("2. Configure your browser to use 127.0.0.1:8080 as HTTP proxy\n");
    printf("3. Visit a site with certificate errors (e.g., self-signed cert)\n");
    printf("4. You should see a custom error page instead of the browser's default\n");
    printf("\n");
    printf("🧪 Test Certificate Errors:\n");
    printf("- Visit https://self-signed.badssl.com/ (self-signed certificate)\n");
    printf("- Visit https://expired.badssl.com/ (expired certificate)\n");
    printf("- Visit https://untrusted-root.badssl.com/ (untrusted root CA)\n");
    printf("\n");
    printf("Press Ctrl+C to stop the proxy\n");
    
    // Keep the program running
    while (1) {
        sleep(1);
    }
    
    return 0;
}

/*
 * How to Build and Run:
 * 
 * 1. First, build the Rust library:
 *    cd /path/to/hudsucker-ffi
 *    cargo build --release
 * 
 * 2. Generate the C header:
 *    cbindgen --config cbindgen.toml --crate hudsucker_ffi --output hudsucker_ffi.h
 * 
 * 3. Compile this example:
 *    gcc -o cert_error_example cert_error_example.c -L./target/release -lhudsucker_ffi -lpthread -ldl
 * 
 * 4. Run the example:
 *    ./cert_error_example
 * 
 * 5. Configure your browser to use 127.0.0.1:8080 as HTTP proxy
 * 
 * 6. Visit a site with certificate errors to see the custom error page
 */