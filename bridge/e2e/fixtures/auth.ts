import { test as base, expect, Page } from '@playwright/test';

/**
 * Playwright fixture that provides an admin-authenticated page.
 *
 * Auth is bootstrapped by injecting a localStorage token that the Zustand
 * auth store will pick up on hydration, so we never need a live auth-service
 * for pure frontend flow tests.  For true E2E (against a running stack) the
 * `liveLogin` helper hits the real `/api/v1/chat/authenticate` endpoint.
 */

// ---------------------------------------------------------------------------
// Types matching bridge/src/types/auth.ts
// ---------------------------------------------------------------------------
interface AuthTokens {
  accessToken: string;
  refreshToken?: string;
  expiresIn: number;
  tokenType: 'Bearer';
}

interface AuthUser {
  id: string;
  username: string;
  email: string;
  role: 'admin' | 'supervisor' | 'teacher' | 'enduser' | 'user';
  isActive: boolean;
}

interface AuthStorage {
  state: {
    tokens: AuthTokens;
    user: AuthUser;
    isAuthenticated: boolean;
  };
  version: number;
}

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------
const MOCK_ADMIN_USER: AuthUser = {
  id: 'e2e-admin-id',
  username: 'e2e-admin',
  email: 'admin@e2e.test',
  role: 'admin',
  isActive: true,
};

const MOCK_TOKENS: AuthTokens = {
  accessToken: 'e2e-mock-access-token',
  refreshToken: 'e2e-mock-refresh-token',
  expiresIn: 3600,
  tokenType: 'Bearer',
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Inject a fake auth session into localStorage so the Zustand store thinks
 * we are already logged in as an admin.
 */
async function injectAdminAuth(page: Page, baseURL: string) {
  const storage: AuthStorage = {
    state: {
      tokens: MOCK_TOKENS,
      user: MOCK_ADMIN_USER,
      isAuthenticated: true,
    },
    version: 0,
  };

  // Navigate to a blank page on the same origin so localStorage writes are valid.
  await page.goto(baseURL);
  await page.evaluate((json) => {
    localStorage.setItem('auth-storage', json);
  }, JSON.stringify(storage));
}

/**
 * Perform a real login against the running auth-service.
 * Use this for live E2E runs where the proxy is up.
 */
async function liveLogin(page: Page, baseURL: string, username: string, password: string) {
  const response = await page.request.post(`${baseURL}/api/v1/chat/authenticate`, {
    data: { username, password },
  });
  expect(response.ok()).toBeTruthy();

  const body = await response.json();

  const storage: AuthStorage = {
    state: {
      tokens: {
        accessToken: body.access_token,
        refreshToken: body.refresh_token,
        expiresIn: body.expires_in,
        tokenType: 'Bearer',
      },
      user: body.user,
      isAuthenticated: true,
    },
    version: 0,
  };

  await page.goto(baseURL);
  await page.evaluate((json) => {
    localStorage.setItem('auth-storage', json);
  }, JSON.stringify(storage));
}

// ---------------------------------------------------------------------------
// Custom fixtures
// ---------------------------------------------------------------------------
type Fixtures = {
  adminPage: Page;
};

export const test = base.extend<Fixtures>({
  adminPage: async ({ page, baseURL }, use) => {
    await injectAdminAuth(page, baseURL!);
    await use(page);
  },
});

export { expect, liveLogin };
