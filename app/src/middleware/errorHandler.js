/**
 * Error handling middleware
 */

let errorCount = 0;

const errorHandler = (err, req, res, next) => {
  errorCount++;
  
  // Log error details
  console.error('Error occurred:', {
    error: err.message,
    stack: process.env.NODE_ENV === 'development' ? err.stack : undefined,
    timestamp: new Date().toISOString(),
    url: req.url,
    method: req.method,
    userAgent: req.get('User-Agent'),
    ip: req.ip
  });

  // Determine error status
  const status = err.status || err.statusCode || 500;
  
  // Send error response
  res.status(status).json({
    error: status === 500 ? 'Internal server error' : err.message,
    message: status === 500 ? 'Something went wrong!' : err.message,
    timestamp: new Date().toISOString(),
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
  });
};

const getErrorCount = () => errorCount;

module.exports = {
  errorHandler,
  getErrorCount
};