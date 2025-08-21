/**
 * Simple logging utility
 */

const config = require('../config');

class Logger {
  constructor() {
    this.levels = {
      error: 0,
      warn: 1,
      info: 2,
      debug: 3
    };
    this.currentLevel = this.levels[config.logging.level] || this.levels.info;
  }

  log(level, message, meta = {}) {
    if (this.levels[level] <= this.currentLevel) {
      const timestamp = new Date().toISOString();
      const logEntry = {
        timestamp,
        level: level.toUpperCase(),
        message,
        environment: config.nodeEnv,
        ...meta
      };

      if (config.nodeEnv === 'production') {
        console.log(JSON.stringify(logEntry));
      } else {
        console.log(`[${timestamp}] ${level.toUpperCase()}: ${message}`, meta);
      }
    }
  }

  error(message, meta = {}) {
    this.log('error', message, meta);
  }

  warn(message, meta = {}) {
    this.log('warn', message, meta);
  }

  info(message, meta = {}) {
    this.log('info', message, meta);
  }

  debug(message, meta = {}) {
    this.log('debug', message, meta);
  }
}

module.exports = new Logger();