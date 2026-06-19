# Signaling Server

A lightweight Node.js + Socket.IO server that lets two clients (Android app
and/or Linux desktop app) find each other and set up a direct WebRTC call.

**Important:** this server never carries your actual audio/video. It only
relays small text messages so two devices can agree on how to connect to
each other directly.

## Files

- `server.js` — the server itself
- `test-call-flow.js` — a self-test that simulates two clients going through
  an entire call (register → call request → accept → offer/answer →
  ICE exchange → hangup) and checks every step worked
- `package.json` — dependencies

## Running locally

```bash
npm install
node server.js
```

You should see:
```
Signaling server listening on port 3000
```

Check it's alive:
```bash
curl http://localhost:3000/health
```

## Running the self-test

With the server running in one terminal, run this in another:

```bash
npm install --save-dev socket.io-client   # only needed once
node test-call-flow.js
```

All 7 checks should print `PASS`.

## The protocol (events)

| Event | Direction | Payload | Purpose |
|---|---|---|---|
| `register` | client → server | `username` (string) | Announce yourself when you connect |
| `user-list` | server → all clients | `string[]` of usernames | Who's currently online |
| `call-request` | client → server → target | `{ toSocketId, fromUsername }` | "I want to call you" |
| `call-accepted` | client → server → caller | `{ toSocketId }` | Callee accepted |
| `call-rejected` | client → server → caller | `{ toSocketId }` | Callee declined |
| `offer` | client → server → target | `{ toSocketId, offer }` | WebRTC SDP offer |
| `answer` | client → server → target | `{ toSocketId, answer }` | WebRTC SDP answer |
| `ice-candidate` | client → server → target | `{ toSocketId, candidate }` | Network path info (sent multiple times) |
| `hangup` | client → server → target | `{ toSocketId }` | End the call |

Every relayed event arrives at the other side with `fromSocketId` added, so
the receiver knows who sent it and can reply to the right person.

### Typical call sequence

1. Both apps connect and `register` with a username
2. Server broadcasts `user-list` to everyone
3. Caller sends `call-request` to the socket ID of who they want to call
4. Callee sends back `call-accepted` (or `call-rejected`)
5. Caller creates a WebRTC offer, sends via `offer`
6. Callee replies with `answer`
7. Both sides trade `ice-candidate` messages until a direct path is found
8. Audio/video now flows directly between the two devices
9. Either side sends `hangup` to end the call

## Deploying to Render (free tier, no credit card)

1. Push this folder to a GitHub repo.
2. On Render: **New +** → **Web Service** → connect your repo.
3. Settings:
   - **Build command**: `npm install`
   - **Start command**: `node server.js`
   - **Instance type**: Free
4. Render will give you a URL like `https://your-app-name.onrender.com` —
   this is what both the Android and Linux apps will connect to.

### Keeping it awake (avoiding cold starts)

Render's free tier sleeps the server after 15 minutes of no traffic, and
takes 30-60 seconds to wake back up on the next request. To avoid that
delay before a call:

- Use a free service like [cron-job.org](https://cron-job.org) to hit
  `https://your-app-name.onrender.com/health` every 10 minutes, **or**
- Just expect a short wait if no one has called in a while — the server
  will wake up automatically on the first connection attempt.

## What's NOT in this server (on purpose, for now)

- No database / persistence — presence is only tracked in memory, reset on
  restart. Fine for 2-3 users.
- No authentication — usernames are just self-declared. Fine for a small
  trusted group; would need real auth before opening this up further.
- No TURN/coturn relay — peer-to-peer WebRTC connections are attempted
  directly first. Add a TURN server later only if calls fail to connect for
  someone behind a strict network.
