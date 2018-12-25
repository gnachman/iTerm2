function iterm2Invoke(invocation, callback) {
    var messgeToPost = {'invocation': invocation,
                        'callback': callback};
    window.webkit.messageHandlers.iterm2Invoke.postMessage(messgeToPost);
}
window.onerror = function(msg) {
    // Sends a message to the app to log the message to the console.
    alert(msg);
};
