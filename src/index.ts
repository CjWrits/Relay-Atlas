import http from 'http';
import { config } from './config';
import { logger } from './lib/logger';
import { SessionSyncBroker } from './auth/session-sync';
import { WebSocketGateway } from './realtime/ws-gateway';

async function bootstrap() {
  logger.info(`Starting Relay-Atlas in ${config.NODE_ENV} mode...`);

  // Initialize SSE session broker
  const sseBroker = new SessionSyncBroker(config.REDIS_URL);

  // Initialize WebSocket Gateway
  const wsGateway = new WebSocketGateway(config.WS_PORT);

  // Simple HTTP dispatcher
  const server = http.createServer((req, res) => {
    if (req.url?.startsWith('/events/session/')) {
      const userId = req.url.split('/')[3] || 'anonymous';
      sseBroker.registerStream(userId, req, res);
      return;
    }

    if (req.url === '/healthz') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'healthy', timestamp: new Date().toISOString() }));
      return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Endpoint not found' }));
  });

  server.listen(config.PORT, () => {
    logger.info(`HTTP and SSE service listening on http://localhost:${config.PORT}`);
  });

  const shutdown = () => {
    logger.info('Shutting down server instances...');
    wsGateway.close();
    server.close();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

bootstrap().catch((err) => {
  logger.error('Fatal crash on bootstrap:', err);
  process.exit(1);
});
