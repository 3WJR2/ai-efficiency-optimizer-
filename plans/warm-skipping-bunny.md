# Plan: Set-It-and-Forget-It Credential & Resilience System

## Context
The tradovate-webhook bot currently stores TRADOVATE_PASSWORD, CID, SEC, and WEBHOOK_SECRET as plaintext in `.env`. The user wants to enter credentials once and never touch them again — with the system auto-reconnecting, auto-restarting, and staying alive indefinitely.

**Problem**: Credentials in plaintext `.env` are a security risk, and if the server crashes or the token expires without a watchdog, trading stops silently.

**Goal**: One-time credential setup → stored in macOS Keychain (encrypted) → server auto-starts, auto-reconnects, never needs manual intervention.

---

## What Gets Built (4 components)

### 1. `src/utils/credentialStore.js` (new)
Abstraction layer for macOS Keychain via native `security` CLI (no new npm deps).

- `store(key, value)` → `security add-generic-password -a tradovate-bot -s <key> -w <value>`
- `retrieve(key)` → `security find-generic-password -a tradovate-bot -s <key> -w`
- `delete(key)` → `security delete-generic-password -a tradovate-bot -s <key>`
- `loadIntoEnv()` → reads all 5 credential keys from Keychain → sets `process.env.*` so existing tradovate.js auth code works unchanged

**Keys stored**: `TRADOVATE_USERNAME`, `TRADOVATE_PASSWORD`, `TRADOVATE_CID`, `TRADOVATE_SEC`, `WEBHOOK_SECRET`

### 2. `scripts/setup-credentials.js` (new)
One-time interactive setup wizard. Run once, never again.

- Checks if credentials already exist in Keychain
- Prompts for each sensitive field (password input hidden with readline raw mode)
- Tests the connection immediately with the entered credentials
- Stores in Keychain on success only
- Strips sensitive fields from `.env` and replaces with comments
- Prints confirmation — tells user to run `npm start` from now on

### 3. `src/utils/watchdog.js` (new)
Auto-reconnect and health monitoring.

- `start()` — runs health check every 60 seconds using `node-cron` (already installed)
- Calls `tradovate.isAuthenticated()` → if false, calls `tradovate.authenticate()`
- Counts consecutive failures → after 3, logs CRITICAL and waits 5 min before retry
- Emits events: `reconnected`, `reconnect_failed`, `healthy`
- Integrates with the risk manager kill switch (if 10 consecutive auth failures → activates kill switch to prevent ghost orders)

### 4. `ecosystem.config.js` (new, project root)
PM2 process config for auto-start on system login.

```js
module.exports = {
  apps: [{
    name: 'tradovate-bot',
    script: 'src/server.js',
    restart_delay: 5000,
    max_restarts: 10,
    autorestart: true,
    watch: false,
    env: { NODE_ENV: 'production' }
  }]
}
```

Plus a `npm run pm2:setup` script that installs PM2 globally and runs `pm2 startup` to register as a login item.

---

## Modify: `src/server.js`
Add credential loading at startup (lines 2-14 area), BEFORE the existing `tradovate.authenticate()` call:

```js
const { credentialStore } = require('./utils/credentialStore');
await credentialStore.loadIntoEnv(); // populates process.env from Keychain
```

Then add watchdog start AFTER successful auth:
```js
const { watchdog } = require('./utils/watchdog');
watchdog.start();
```

**No changes to `tradovate.js`** — it continues reading from `process.env.*` unchanged.

---

## Modify: `.env.example`
Remove sensitive credential lines. Add comments directing users to `setup-credentials.js`.

---

## Modify: `package.json`
Add 3 new scripts:
- `"setup-creds": "node scripts/setup-credentials.js"` — one-time setup
- `"pm2:setup": "npm install -g pm2 && pm2 startup && pm2 save"`
- `"pm2:start": "pm2 start ecosystem.config.js"`

---

## Critical Files Modified

| File | Change |
|------|--------|
| `src/server.js` | Add `credentialStore.loadIntoEnv()` before auth + `watchdog.start()` after |
| `package.json` | Add 3 new npm scripts |
| `.env.example` | Remove sensitive fields, add setup instructions |
| `.env` | Sensitive values cleared after setup-creds runs |

## New Files Created

| File | Purpose |
|------|---------|
| `src/utils/credentialStore.js` | macOS Keychain r/w via `security` CLI |
| `scripts/setup-credentials.js` | One-time interactive credential wizard |
| `src/utils/watchdog.js` | Auto-reconnect loop using node-cron |
| `ecosystem.config.js` | PM2 process config |

---

## Verification

1. Run `npm run setup-creds` → prompts for credentials → stores in Keychain → tests connection
2. Verify Keychain: `security find-generic-password -a tradovate-bot -s TRADOVATE_USERNAME`
3. Clear `.env` credentials manually → run `npm start` → server should auth from Keychain
4. Run unit tests: `npm test` → still 6/6 (no behaviour change)
5. Kill server process → PM2 auto-restarts it within 5s
6. Token watchdog: wait 60s → check logs for "Watchdog: healthy" message
