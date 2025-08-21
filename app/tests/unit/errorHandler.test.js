/**
 * Unit tests for error handler middleware
 */

const { errorHandler, getErrorCount } = require('../../src/middleware/errorHandler');

describe('Error Handler Middleware', () => {
  let req, res, next;

  beforeEach(() => {
    req = {
      url: '/test',
      method: 'GET',
      get: jest.fn().mockReturnValue('test-user-agent'),
      ip: '127.0.0.1'
    };
    res = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn()
    };
    next = jest.fn();

    // Mock console.error to avoid noise in test output
    jest.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  test('should handle generic errors with 500 status', () => {
    const error = new Error('Test error');

    errorHandler(error, req, res, next);

    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.json).toHaveBeenCalledWith({
      error: 'Internal server error',
      message: 'Something went wrong!',
      timestamp: expect.any(String)
    });
  });

  test('should handle errors with custom status', () => {
    const error = new Error('Not found');
    error.status = 404;

    errorHandler(error, req, res, next);

    expect(res.status).toHaveBeenCalledWith(404);
    expect(res.json).toHaveBeenCalledWith({
      error: 'Not found',
      message: 'Not found',
      timestamp: expect.any(String)
    });
  });

  test('should handle errors with statusCode property', () => {
    const error = new Error('Bad request');
    error.statusCode = 400;

    errorHandler(error, req, res, next);

    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith({
      error: 'Bad request',
      message: 'Bad request',
      timestamp: expect.any(String)
    });
  });

  test('should log error details', () => {
    const error = new Error('Test error');
    const consoleSpy = jest.spyOn(console, 'error');

    errorHandler(error, req, res, next);

    expect(consoleSpy).toHaveBeenCalledWith('Error occurred:', {
      error: 'Test error',
      stack: undefined, // Stack is undefined in test environment
      timestamp: expect.any(String),
      url: '/test',
      method: 'GET',
      userAgent: 'test-user-agent',
      ip: '127.0.0.1'
    });
  });

  test('should increment error count', () => {
    const initialCount = getErrorCount();
    const error = new Error('Test error');

    errorHandler(error, req, res, next);

    expect(getErrorCount()).toBe(initialCount + 1);
  });

  test('should include stack trace in development mode', () => {
    const originalEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'development';

    const error = new Error('Test error');
    error.stack = 'Error stack trace';

    errorHandler(error, req, res, next);

    expect(res.json).toHaveBeenCalledWith({
      error: 'Internal server error',
      message: 'Something went wrong!',
      timestamp: expect.any(String),
      stack: 'Error stack trace'
    });

    process.env.NODE_ENV = originalEnv;
  });
});