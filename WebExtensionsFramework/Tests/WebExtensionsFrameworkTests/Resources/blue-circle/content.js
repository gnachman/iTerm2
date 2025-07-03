// Blue Circle Extension Content Script
console.log('Blue Circle Extension: Content script loaded');

// Create a global variable in this extension's content world
window.blueCircleExtensionActive = true;
window.extensionType = 'blue-circle';

// Add a blue circle to the page
const blueCircle = document.createElement('div');
blueCircle.style.cssText = `
    position: fixed;
    top: 100px;
    right: 20px;
    width: 80px;
    height: 80px;
    background: blue;
    border-radius: 50%;
    z-index: 9998;
    border: 2px solid darkblue;
`;
blueCircle.textContent = '🔵';
blueCircle.style.display = 'flex';
blueCircle.style.alignItems = 'center';
blueCircle.style.justifyContent = 'center';
blueCircle.style.fontSize = '30px';
blueCircle.id = 'blue-circle-extension';

document.body.appendChild(blueCircle);

console.log('Blue Circle Extension: Added blue circle to page');