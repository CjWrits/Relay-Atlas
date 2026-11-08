import { WebSocketServer, WebSocket } from 'ws';
import { logger } from '../lib/logger';

export class WebSocketGateway {
  private wss: WebSocketServer;

  constructor(port: number) {
    this.wss = new WebSocketServer({ port });
    this.setupListeners();
    this.setupHeartbeat();
    logger.info(`[WebSocketGateway] Listening on ws://0.0.0.0:${port}`);
  }

  private setupListeners() {
    this.wss.on('connection', (ws: WebSocket) => {
      logger.debug('[WebSocketGateway] Client connected');

      ws.on('message', (message: string) => {
        try {
          const parsed = JSON.parse(message);
          this.routeMessage(ws, parsed);
        } catch {
          ws.send(JSON.stringify({ error: 'Malformed JSON payload' }));
        }
      });
    });
  }

  private routeMessage(client: WebSocket, data: Record<string, unknown>) {
    client.send(JSON.stringify({ ack: true, channel: data.channel }));
  }

  public close() {
    this.wss.close();
  }
}

  private setupHeartbeat() {
    setInterval(() => {
      this.wss.clients.forEach((ws) => {
        if (ws.readyState === 1) {
          ws.ping();
        }
      });
    }, 30000);
  }
