import { IncomingMessage, ServerResponse } from 'http';
import { verifyAccessToken } from './jwt';
import { UserContext } from './types';

export interface AuthenticatedRequest extends IncomingMessage {
  user?: UserContext;
}

export function authenticate(
  req: AuthenticatedRequest,
  res: ServerResponse,
  next: () => void
): void {
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.writeHead(401, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Missing or malformed Authorization header' }));
    return;
  }

  const token = authHeader.substring(7);
  try {
    const user = verifyAccessToken(token);
    req.user = user;
    next();
  } catch (err) {
    res.writeHead(401, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Invalid or expired token', details: (err as Error).message }));
  }
}
