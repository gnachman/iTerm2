// Add a red box to the top of every page

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
console.log('Red box extension loaded!');