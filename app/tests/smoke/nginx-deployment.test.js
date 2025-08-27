const http = require('http');

// Simple smoke test for nginx deployment
function testEndpoint(hostname, path, expectedContent) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: hostname,
      port: 80,
      path: path,
      method: 'GET',
      timeout: 10000
    };

    const req = http.request(options, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk;
      });
      
      res.on('end', () => {
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
          return;
        }
        
        if (expectedContent && !data.includes(expectedContent)) {
          reject(new Error(`Expected content "${expectedContent}" not found in response`));
          return;
        }
        
        resolve(data);
      });
    });

    req.on('error', (err) => {
      reject(err);
    });

    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });

    req.end();
  });
}

async function runSmokeTests() {
  const hostname = process.env.ALB_DNS_NAME;
  const environment = process.env.ENVIRONMENT || 'staging';
  
  if (!hostname) {
    console.error('ALB_DNS_NAME environment variable is required');
    process.exit(1);
  }

  console.log(`Running smoke tests against: http://${hostname}`);
  console.log(`Expected environment: ${environment}`);

  try {
    // Test health endpoint
    console.log('Testing health endpoint...');
    const healthResponse = await testEndpoint(hostname, '/health', 'healthy');
    console.log('✓ Health endpoint is working');

    // Test ready endpoint  
    console.log('Testing ready endpoint...');
    await testEndpoint(hostname, '/ready', 'ready');
    console.log('✓ Ready endpoint is working');

    // Test metrics endpoint
    console.log('Testing metrics endpoint...');
    await testEndpoint(hostname, '/metrics', 'nginx');
    console.log('✓ Metrics endpoint is working');

    // Test main page shows correct environment
    console.log('Testing main page...');
    await testEndpoint(hostname, '/', environment);
    console.log(`✓ Main page shows correct environment: ${environment}`);

    console.log('\n✅ All smoke tests passed!');
    
  } catch (error) {
    console.error(`\n❌ Smoke test failed: ${error.message}`);
    process.exit(1);
  }
}

if (require.main === module) {
  runSmokeTests();
}

module.exports = { testEndpoint, runSmokeTests };