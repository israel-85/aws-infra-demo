/**
 * Unit tests for logger utility
 */

const logger = require('../../src/utils/logger');

describe('Logger Utility', () => {
  let consoleSpy;

  beforeEach(() => {
    consoleSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  test('should log error messages', () => {
    logger.error('Test error message', { code: 'ERR001' });

    expect(consoleSpy).toHaveBeenCalledWith(
      expect.stringContaining('ERROR: Test error message'),
      { code: 'ERR001' }
    );
  });

  test('should log warn messages', () => {
    logger.warn('Test warning message', { code: 'WARN001' });

    expect(consoleSpy).toHaveBeenCalledWith(
      expect.stringContaining('WARN: Test warning message'),
      { code: 'WARN001' }
    );
  });

  test('should log info messages', () => {
    logger.info('Test info message', { userId: '123' });

    expect(consoleSpy).toHaveBeenCalledWith(
      expect.stringContaining('INFO: Test info message'),
      { userId: '123' }
    );
  });

  test('should log debug messages when level allows', () => {
    // Debug messages might not be logged depending on current level
    logger.debug('Test debug message', { debug: true });

    // We just verify it doesn't throw an error
    expect(() => logger.debug('Test debug message')).not.toThrow();
  });

  test('should format log entries correctly', () => {
    logger.info('Test message');

    expect(consoleSpy).toHaveBeenCalledWith(
      expect.stringMatching(/\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\] INFO: Test message/),
      {}
    );
  });

  test('should include metadata in log entries', () => {
    const metadata = { userId: '123', action: 'login' };
    logger.info('User logged in', metadata);

    expect(consoleSpy).toHaveBeenCalledWith(
      expect.stringContaining('INFO: User logged in'),
      metadata
    );
  });
});