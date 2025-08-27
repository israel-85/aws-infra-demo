const fs = require('fs');
const path = require('path');

function validateHtml() {
  try {
    const htmlPath = path.join(__dirname, 'index.html');
    const htmlContent = fs.readFileSync(htmlPath, 'utf8');
    
    // Basic HTML validation
    if (!htmlContent.includes('<!DOCTYPE html>')) {
      throw new Error('Missing DOCTYPE declaration');
    }
    
    if (!htmlContent.includes('<html')) {
      throw new Error('Missing html tag');
    }
    
    if (!htmlContent.includes('<head>')) {
      throw new Error('Missing head tag');
    }
    
    if (!htmlContent.includes('<body>')) {
      throw new Error('Missing body tag');
    }
    
    if (!htmlContent.includes('__ENVIRONMENT__')) {
      throw new Error('Missing environment placeholder');
    }
    
    console.log('✓ HTML structure validation passed');
    return true;
  } catch (error) {
    console.error('✗ HTML validation failed:', error.message);
    process.exit(1);
  }
}

validateHtml();