// Add a red box to the top of every page
console.log('Red Box Extension: Content script loaded');

// Create global variables in this extension's content world
window.redBoxExtensionActive = true;
window.extensionType = 'red-box';

const redBox = document.createElement('div');
redBox.textContent = 'Red Box Extension Active!';
redBox.style.cssText = `
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  height: 50px;
  background: red;
  color: white;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: Arial, sans-serif;
  font-weight: bold;
  z-index: 9999;
`;

document.body.appendChild(redBox);
console.log('Red Box Extension: Added red box to page');