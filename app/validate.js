#!/usr/bin/env node

/**
 * Simple validation script to check if the application works
 */

const app = require('./src/server');
const request = require('supertest');

async function validateApp() {
  console.log('🔍 Validating application...');

  try {
    // Test health endpoint
    const healthResponse = await request(app).get('/health');
    if (healthResponse.status !== 200) {
      throw new Error(`Health check failed: ${healthResponse.status}`);
    }
    console.log('✅ Health endpoint working');

    // Test ready endpoint
    const readyResponse = await request(app).get('/ready');
    if (readyResponse.status !== 200) {
      throw new Error(`Ready check failed: ${readyResponse.status}`);
    }
    console.log('✅ Ready endpoint working');

    // Test main endpoint
    const mainResponse = await request(app).get('/');
    if (mainResponse.status !== 200) {
      throw new Error(`Main endpoint failed: ${mainResponse.status}`);
    }
    console.log('✅ Main endpoint working');

    // Test metrics endpoint
    const metricsResponse = await request(app).get('/metrics');
    if (metricsResponse.status !== 200) {
      throw new Error(`Metrics endpoint failed: ${metricsResponse.status}`);
    }
    console.log('✅ Metrics endpoint working');

    console.log('🎉 Application validation successful!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Application validation failed:', error.message);
    process.exit(1);
  }
}

validateApp();