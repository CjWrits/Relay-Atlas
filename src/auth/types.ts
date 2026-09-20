export interface SessionSyncPayload {
  userId: string;
  sessionId: string;
  eventType: 'TOKEN_REFRESHED' | 'SESSION_TERMINATED' | 'MFA_REQUIRED' | 'POLICY_UPDATE';
  accessTokenExpiresAt: number;
  issuedAt: number;
}

export interface UserContext {
  userId: string;
  organizationId: string;
  email: string;
  roles: string[];
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}
