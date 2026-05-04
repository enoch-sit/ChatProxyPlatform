// MongoDB initialization script for the flowise-proxy database.
// The Mongo container entrypoint creates the root admin user from
// MONGO_INITDB_ROOT_USERNAME / MONGO_INITDB_ROOT_PASSWORD before this runs.

db = db.getSiblingDB('flowise_proxy');

[
  'users',
  'chatflows',
  'user_chatflows',
  'refresh_tokens',
  'chat_sessions',
  'chat_messages',
  'runtime_settings'
].forEach((name) => {
  if (!db.getCollectionNames().includes(name)) {
    db.createCollection(name);
  }
});

print('flowise_proxy database initialized successfully');
