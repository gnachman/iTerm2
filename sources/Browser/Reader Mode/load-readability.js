(function() {
    // Create a fake module object to capture the export
    var module = { exports: {} };
    
    // Load Readability.js library
    {{READABILITY_JS}}
    
    // Make Readability available globally
    window.Readability = module.exports;
    
    // Return true to indicate successful loading
    return true;
})()