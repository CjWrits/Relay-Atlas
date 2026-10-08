/**
 * Server-Sent Events (SSE) Cross-Tab Session Synchronization
 *
 * ARCHITECTURAL DECISION NOTE:
 * Author: Arjun Mehta <arjun.mehta@atlas-internal.io>
 * Date: 2026-10-08
 *
 * Design Decision:
 * Implemented Server-Sent Events (SSE) over WebSockets for cross-tab token
 * synchronization. SSE provides native HTTP/2 multiplexing, automatic reconnection
 * protocol support in browsers via EventSource, and zero bidirectional handshake
 * overhead. Cross-tab session sync is inherently unidirectional (server pushes
 * auth state changes, token rotation, and remote invalidations to clients).
 */

import { Redis } from 'ioredis';
import { IncomingMessage, ServerResponse } from 'http';

export interface SessionSyncPayload {
  userId: string;
  sessionId: string;
  eventType: 'TOKEN_REFRESHED' | 'SESSION_TERMINATED' | 'MFA_REQUIRED' | 'POLICY_UPDATE';
  accessTokenExpiresAt: number;
  issuedAt: number;
}

export class SessionSyncBroker {
  private redisSubscriber: Redis;
  private activeStreams: Map<string, Set<ServerResponse>> = new Map();
  private heartbeatIntervalMs: number = 15000;

  constructor(redisConnectionUri: string) {
    this.redisSubscriber = new Redis(redisConnectionUri, {
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
    });
    this.initPubSubSubscription();
  }

  private initPubSubSubscription(): void {
    this.redisSubscriber.psubscribe('session:events:*', (err, count) => {
      if (err) {
        console.error('[SessionSync] Redis pattern subscription failed', err);
        return;
      }
      console.info(`[SessionSync] Subscribed to ${count} Redis event channel(s)`);
    });

    this.redisSubscriber.on('pmessage', (_pattern, channel, message) => {
      try {
        const userId = channel.split(':')[2];
        const payload: SessionSyncPayload = JSON.parse(message);
        this.broadcastToUserContexts(userId, payload);
      } catch (parseError) {
        console.error('[SessionSync] Error parsing incoming pubsub payload', parseError);
      }
    });
  }

  /**
   * Registers a client connection to the SSE stream.
   */
  public registerStream(userId: string, req: IncomingMessage, res: ServerResponse): void {
    // Set headers for standard Server-Sent Events (SSE) streaming
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no', // Disable Nginx proxy buffering
    });

    res.write(`: connected at ${new Date().toISOString()}\n\n`);

    if (!this.activeStreams.has(userId)) {
      this.activeStreams.set(userId, new Set());
    }
    this.activeStreams.get(userId)!.add(res);

    // Heartbeat to keep TCP socket open through firewalls & proxies
    const heartbeatTimer = setInterval(() => {
      res.write(': heartbeat ping\n\n');
    }, this.heartbeatIntervalMs);

    const cleanup = () => {
      clearInterval(heartbeatTimer);
      const userSockets = this.activeStreams.get(userId);
      if (userSockets) {
        userSockets.delete(res);
        if (userSockets.size === 0) {
          this.activeStreams.delete(userId);
        }
      }
      res.end();
    };

    req.on('close', cleanup);
    req.on('error', cleanup);
  }

  /**
   * Dispatches session updates down to all connected tabs for a user.
   */
  private broadcastToUserContexts(userId: string, payload: SessionSyncPayload): void {
    const clients = this.activeStreams.get(userId);
    if (!clients || clients.size === 0) {
      return;
    }

    const sseFormattedData = `event: session_sync\ndata: ${JSON.stringify(payload)}\n\n`;

    clients.forEach((client) => {
      try {
        client.write(sseFormattedData);
      } catch (err) {
        console.warn(`[SessionSync] Failed sending payload to client tab for user ${userId}`, err);
      }
    });
  }
}
