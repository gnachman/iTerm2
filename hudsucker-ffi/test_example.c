#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "hudsucker_ffi.h"

// Example callback that blocks requests to example.com
bool request_filter(const char* url, const char* method, void* user_data) {
    printf("Request: %s %s\n", method, url);
    
    // Block requests to example.com
    if (strstr(url, "example.com") != NULL) {
        printf("Blocking request to example.com\n");
        return false;
    }
    
    return true;
}

int main() {
    char* cert_pem = NULL;
    char* key_pem = NULL;
    
    // Generate CA certificate
    printf("Generating CA certificate...\n");
    enum HudsuckerError result = hudsucker_generate_ca_cert(&cert_pem, &key_pem);
    if (result != Success) {
        fprintf(stderr, "Failed to generate CA certificate: %d\n", result);
        return 1;
    }
    
    printf("Generated CA certificate:\n%s\n", cert_pem);
    printf("Generated CA key:\n%s\n", key_pem);
    
    // Create proxy
    struct HudsuckerProxy* proxy = NULL;
    printf("Creating proxy on 127.0.0.1:8080...\n");
    result = hudsucker_create_proxy(
        "127.0.0.1:8080",
        cert_pem,
        key_pem,
        request_filter,
        NULL,
        &proxy
    );
    
    if (result != Success) {
        fprintf(stderr, "Failed to create proxy: %d\n", result);
        hudsucker_free_string(cert_pem);
        hudsucker_free_string(key_pem);
        return 1;
    }
    
    printf("Proxy created successfully! Running for 10 seconds...\n");
    printf("Configure your browser to use HTTP proxy at 127.0.0.1:8080\n");
    
    // Let the proxy run for 10 seconds
    sleep(10);
    
    // Cleanup
    printf("Shutting down proxy...\n");
    hudsucker_destroy_proxy(proxy);
    hudsucker_free_string(cert_pem);
    hudsucker_free_string(key_pem);
    
    printf("Test completed successfully!\n");
    return 0;
}