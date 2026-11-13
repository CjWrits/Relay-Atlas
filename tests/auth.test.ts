import { signAccessToken, verifyAccessToken } from '../src/auth/jwt';
import { UserContext } from '../src/auth/types';

describe('Auth JWT Utilities', () => {
  const testUser: UserContext = {
    userId: 'usr_123456',
    organizationId: 'org_7890',
    email: 'test@atlas.local',
    roles: ['admin', 'member'],
  };

  it('should sign and successfully verify valid tokens', () => {
    const token = signAccessToken(testUser);
    expect(typeof token).toBe('string');
    const decoded = verifyAccessToken(token);
    expect(decoded.userId).toBe(testUser.userId);
    expect(decoded.organizationId).toBe(testUser.organizationId);
  });
});
