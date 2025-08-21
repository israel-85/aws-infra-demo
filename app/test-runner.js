#!/usr/bin/env node

/**
 * Simple test runner to verify our tests work
 */

const { execSync } = require('child_process');

console.log('Running unit tests...');
try {
  execSync('npx jest tests/unit --runInBand --forceExit --detectOpenHandles', { 
    stdio: 'inherit',
    timeout: 30000
  });
  console.log('✅ Unit tests passed');
} catch (error) {
  console.error('❌ Unit tests failed:', error.message);
  process.exit(1);
}

console.log('\nRunning integration tests...');
try {
  execSync('npx jest tests/integration --runInBand --forceExit --detectOpenHandles', { 
    stdio: 'inherit',
    timeout: 30000
  });
  console.log('✅ Integration tests passed');
} catch (error) {
  console.error('❌ Integration tests failed:', error.message);
  process.exit(1);
}

console.log('\nRunning smoke tests...');
try {
  execSync('npx jest tests/smoke --runInBand --forceExit --detectOpenHandles', { 
    stdio: 'inherit',
    timeout: 30000
  });
  console.log('✅ Smoke tests passed');
} catch (error) {
  console.error('❌ Smoke tests failed:', error.message);
  process.exit(1);
}

console.log('\n🎉 All tests completed successfully!');