// Background script for Count Logger extension

let count = 0;

// Start logging count every second
// FYI webkit won't allow this to go more than once per second.
setInterval(() => {
  count++;
  console.log(`Count: ${count}`);
}, 1000);

console.log('Count Logger background script started');
