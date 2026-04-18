import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const repoRoot = process.cwd();

const checks = [
  {
    file: join(repoRoot, 'src', 'pages', 'AdminPage.tsx'),
    required: [
      'value="chatflows"',
      'value="users"',
      'value="credits"',
      'value="usage"',
      'value="student-chats"',
      'value="settings"',
      'const tabsContainerRef = useRef<HTMLDivElement | null>(null);',
    ],
  },
  {
    file: join(repoRoot, 'src', 'components', 'admin', 'AdminFlowiseSettingsPanel.tsx'),
    required: [
      'getFlowiseApiKeyStatus',
      'updateFlowiseApiKey',
      'testFlowiseApiKey',
      "flex: 1",
      "overflow: 'auto'",
    ],
  },
  {
    file: join(repoRoot, 'src', 'components', 'layout', 'Layout.tsx'),
    required: [
      "location.pathname.startsWith('/admin') ? 'hidden' : 'auto'",
      "overflow: location.pathname.startsWith('/admin') ? 'hidden' : 'hidden'",
    ],
  },
];

const failures = [];

for (const check of checks) {
  const content = readFileSync(check.file, 'utf8');
  for (const token of check.required) {
    if (!content.includes(token)) {
      failures.push(`Missing token in ${check.file}: ${token}`);
    }
  }
}

if (failures.length > 0) {
  console.error('Admin UI audit failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Admin UI audit passed.');
