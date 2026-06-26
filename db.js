// db.js
//
// Tiny SQLite-backed user store using Node's built-in node:sqlite module
// (no external dependency, no native compilation needed - just works
// the same locally and on Render).
//
// Stores one row per Google account that has ever signed in: their
// Google "sub" (a stable unique ID Google assigns per account - more
// reliable than email, since email can theoretically change), email,
// and display name.

const { DatabaseSync } = require("node:sqlite");
const path = require("path");

const DB_PATH = path.join(__dirname, "users.db");
const db = new DatabaseSync(DB_PATH);

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    google_sub TEXT PRIMARY KEY,
    email TEXT NOT NULL,
    display_name TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_login_at TEXT NOT NULL DEFAULT (datetime('now'))
  )
`);

/**
 * Finds an existing user by their Google "sub" (unique account ID),
 * or creates a new row if this is their first time signing in.
 * Either way, updates last_login_at to now.
 */
function findOrCreateUser({ googleSub, email, displayName }) {
  const existing = db
    .prepare("SELECT * FROM users WHERE google_sub = ?")
    .get(googleSub);

  if (existing) {
    db.prepare("UPDATE users SET last_login_at = datetime('now') WHERE google_sub = ?").run(googleSub);
    return existing;
  }

  db.prepare(
    "INSERT INTO users (google_sub, email, display_name) VALUES (?, ?, ?)"
  ).run(googleSub, email, displayName);

  return db.prepare("SELECT * FROM users WHERE google_sub = ?").get(googleSub);
}

module.exports = { findOrCreateUser };
