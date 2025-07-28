window.addEventListener('error', function(event) {
  console.log(
    '[Injected JS Error]',
    'message:', event.message,
    'source:', event.filename + ':' + event.lineno + ':' + event.colno,
    'error object:', event.error,
    'stack:', event.error && event.error.stack
  );
});

window.addEventListener('unhandledrejection', function(event) {
  console.log(
    '[Unhandled Promise Rejection]',
    'reason:', event.reason,
    'stack:', event.reason && event.reason.stack
  );
});
