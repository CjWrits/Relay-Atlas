import jwt from 'jsonwebtoken';
import { config } from '../config';
import { UserContext } from './types';

export function signAccessToken(payload: UserContext): string {
  return jwt.sign(payload, config.JWT_SECRET, {
    expiresIn: '1h',
    algorithm: 'HS256',
  });
}

export function verifyAccessToken(token: string): UserContext {
  return jwt.verify(token, config.JWT_SECRET) as UserContext;
}

export function decodeAccessToken(token: string): UserContext | null {
  try {
    return jwt.decode(token) as UserContext;
  } catch {
    return null;
  }
}
