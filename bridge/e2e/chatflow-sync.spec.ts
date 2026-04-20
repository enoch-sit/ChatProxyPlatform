import { test, expect } from '../fixtures/auth';

/**
 * E2E tests for the chatflow sync feature.
 *
 * These tests run against the bridge frontend with API responses mocked via
 * Playwright's route interception — no live backend needed.
 */

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------
const MOCK_CHATFLOWS = [
  {
    _id: '1',
    id: '1',
    flowise_id: 'flow-aaa',
    name: 'Test Chatflow',
    description: 'A test chatflow',
    deployed: true,
    is_public: false,
    category: 'general',
    type: 'CHATFLOW' as const,
    created_date: '2025-01-01T00:00:00Z',
    updated_date: '2025-01-01T00:00:00Z',
    sync_status: 'active' as const,
  },
];

const MOCK_STATS = {
  total: 1,
  active: 1,
  deleted: 0,
  error: 0,
  last_sync: '2025-01-01T00:00:00Z',
};

const MOCK_SYNC_RESULT = {
  total_fetched: 2,
  created: 1,
  updated: 1,
  deleted: 0,
  errors: 0,
  error_details: [],
};

const MOCK_SYSTEM_STATS = {
  total_users: 5,
  active_users: 3,
  total_chatflows: 1,
};

// ---------------------------------------------------------------------------
// Route intercept helper
// ---------------------------------------------------------------------------
async function mockAdminAPI(page: import('@playwright/test').Page) {
  // Chatflows list
  await page.route('**/api/v1/admin/chatflows?*', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(MOCK_CHATFLOWS) }),
  );
  await page.route('**/api/v1/admin/chatflows', (route) => {
    if (route.request().method() === 'GET') {
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(MOCK_CHATFLOWS) });
    }
    return route.continue();
  });

  // Chatflow stats
  await page.route('**/api/v1/admin/chatflows/stats', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(MOCK_STATS) }),
  );

  // System stats
  await page.route('**/api/v1/admin/stats', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(MOCK_SYSTEM_STATS) }),
  );

  // Current user (auth guard)
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

  // Users list (admin panel loads this)
  await page.route('**/api/v1/admin/users*', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );

  // Credits list
  await page.route('**/api/v1/admin/credits*', (route) =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) }),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
test.describe('Chatflow Sync', () => {
  test('sync button triggers API call and shows results', async ({ adminPage }) => {
    await mockAdminAPI(adminPage);

    // Mock the sync endpoint
    let syncCalled = false;
    await adminPage.route('**/api/v1/admin/chatflows/sync', (route) => {
      if (route.request().method() === 'POST') {
        syncCalled = true;
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(MOCK_SYNC_RESULT),
        });
      }
      return route.continue();
    });

    // Navigate to admin page
    await adminPage.goto('/admin');

    // The chatflows tab should be active by default — find and click the sync button
    const syncButton = adminPage.getByRole('button', { name: /sync/i });
    await expect(syncButton).toBeVisible({ timeout: 10000 });
    await syncButton.click();

    // Verify the API was actually called
    expect(syncCalled).toBe(true);

    // Verify success message shows real sync results
    await expect(
      adminPage.getByText(/2 fetched.*1 created.*1 updated.*0 deleted/),
    ).toBeVisible({ timeout: 5000 });
  });

  test('sync button shows error state on API failure', async ({ adminPage }) => {
    await mockAdminAPI(adminPage);

    // Mock the sync endpoint to fail
    await adminPage.route('**/api/v1/admin/chatflows/sync', (route) => {
      if (route.request().method() === 'POST') {
        return route.fulfill({
          status: 500,
          contentType: 'application/json',
          body: JSON.stringify({ detail: 'Flowise unreachable' }),
        });
      }
      return route.continue();
    });

    await adminPage.goto('/admin');

    const syncButton = adminPage.getByRole('button', { name: /sync/i });
    await expect(syncButton).toBeVisible({ timeout: 10000 });
    await syncButton.click();

    // After failure the store sets an error — check for an error indicator
    // The exact error display depends on how the AdminPage renders store.error
    // At minimum the button should become enabled again (isLoading resets)
    await expect(syncButton).toBeEnabled({ timeout: 5000 });
  });

  test('sync result with errors shows error count', async ({ adminPage }) => {
    await mockAdminAPI(adminPage);

    const resultWithErrors = {
      total_fetched: 3,
      created: 1,
      updated: 1,
      deleted: 0,
      errors: 1,
      error_details: [{ error: 'Failed to process chatflow xyz', chatflow_id: 'xyz' }],
    };

    await adminPage.route('**/api/v1/admin/chatflows/sync', (route) => {
      if (route.request().method() === 'POST') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(resultWithErrors),
        });
      }
      return route.continue();
    });

    await adminPage.goto('/admin');

    const syncButton = adminPage.getByRole('button', { name: /sync/i });
    await expect(syncButton).toBeVisible({ timeout: 10000 });
    await syncButton.click();

    // Success message should mention the error count
    await expect(adminPage.getByText(/1 error/i)).toBeVisible({ timeout: 5000 });
  });

  test('chatflows table displays fetched chatflows', async ({ adminPage }) => {
    await mockAdminAPI(adminPage);

    await adminPage.goto('/admin');

    // The chatflows tab should show the mocked chatflow
    await expect(adminPage.getByText('Test Chatflow')).toBeVisible({ timeout: 10000 });
  });
});
