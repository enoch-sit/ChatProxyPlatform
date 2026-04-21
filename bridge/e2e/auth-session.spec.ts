import { test, expect } from './fixtures/auth';

async function mockAdminBootstrap(page: import('@playwright/test').Page) {
  await page.route('**/api/v1/chat/current-user', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        id: 'e2e-admin-id',
        username: 'e2e-admin',
        email: 'admin@e2e.test',
        role: 'admin',
        isActive: true,
      }),
    }),
  );

  await page.route('**/api/v1/admin/stats', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        total_users: 5,
        active_users: 3,
        total_chatflows: 1,
      }),
    }),
  );

  await page.route('**/api/v1/admin/users*', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );

  await page.route('**/api/v1/admin/chatflows*', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );

  await page.route('**/api/v1/admin/credits*', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );

  await page.route('**/api/v1/chat/revoke', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true }) }),
  );
}

test.describe('Auth Session Behavior', () => {
  test('logout redirects to login page', async ({ adminPage }) => {
    await mockAdminBootstrap(adminPage);

    await adminPage.goto('/admin');

    const logoutButton = adminPage.getByRole('button', { name: /logout|sign\s*out|登出/i });
    await expect(logoutButton).toBeVisible({ timeout: 10000 });
    await logoutButton.click();

    await expect(adminPage).toHaveURL(/\/login$/, { timeout: 7000 });

    const authStorage = await adminPage.evaluate(() => localStorage.getItem('auth-storage'));
    if (authStorage) {
      const parsed = JSON.parse(authStorage);
      expect(parsed.state?.tokens).toBeFalsy();
      expect(parsed.state?.isAuthenticated).toBeFalsy();
    }
  });

  test('expired token plus refresh failure forces redirect', async ({ adminPage }) => {
    await mockAdminBootstrap(adminPage);

    await adminPage.route('**/api/v1/chat/refresh', (route) =>
      route.fulfill({
        status: 401,
        contentType: 'application/json',
        body: JSON.stringify({ detail: 'refresh token invalid' }),
      }),
    );

    await adminPage.evaluate(() => {
      const raw = localStorage.getItem('auth-storage');
      if (!raw) return;

      const parsed = JSON.parse(raw);
      const now = Math.floor(Date.now() / 1000);
      const expiredPayload = {
        username: 'e2e-admin',
        role: 'admin',
        iat: now - 3600,
        exp: now - 60,
      };

      const header = btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/g, '');
      const payload = btoa(JSON.stringify(expiredPayload))
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/g, '');

      parsed.state.tokens.accessToken = `${header}.${payload}.expired-signature`;
      localStorage.setItem('auth-storage', JSON.stringify(parsed));
    });

    await adminPage.reload();
    await adminPage.goto('/admin');

    await expect(adminPage).toHaveURL(/\/login$/, { timeout: 7000 });
  });
});
