// Signaling server for the call app
// Handles: user registration, presence (who's online), call setup (offer/answer),
// ICE candidate exchange, call accept/reject, and hangup.
//
// This server NEVER touches actual audio/video — it only relays small JSON
// messages so two peers can find each other and agree on a direct connection.

const express = require("express");
const http = require("http");
const cors = require("cors");
const { Server } = require("socket.io");
const { OAuth2Client } = require("google-auth-library");
const { findOrCreateUser } = require("./db.js");

// This must match the WEB client ID created in Google Cloud Console -
// the same one baked into the Android app's strings.xml as
// default_web_client_id. Google's verifyIdToken call below checks that
// the token was issued for this specific client.
const GOOGLE_WEB_CLIENT_ID = process.env.GOOGLE_WEB_CLIENT_ID ||
  "934658890192-rrbcj7huotb83d2glfqr0svcou720vur.apps.googleusercontent.com";

const googleClient = new OAuth2Client(GOOGLE_WEB_CLIENT_ID);

const app = express();
app.use(cors());

// Simple health-check endpoint.
// Useful for: (1) confirming the server is up, (2) a keep-alive ping target
// to prevent Render's free tier from sleeping the server after inactivity.
app.get("/health", (req, res) => {
  res.json({ status: "ok", onlineUsers: Object.keys(connectedUsers).length });
});

app.get("/", (req, res) => {
  res.send("Signaling server is running.");
});

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*", // For a 2-3 user personal app this is fine; tighten later if needed.
  },
});

// Map of socket.id -> username, so we know who's connected.
const connectedUsers = {};

function broadcastUserList() {
  // Send both socketId and username for each connected user, since callers
  // need the target's socketId to send a call-request - a username alone
  // isn't enough to address anyone.
  const users = Object.entries(connectedUsers).map(([socketId, username]) => ({
    socketId,
    username,
  }));
  io.emit("user-list", users);
}

io.on("connection", (socket) => {
  console.log(`[connect] socket ${socket.id} connected`);

  // --- Registration ---
  // Client sends a Google ID token (not a plain username) right after
  // connecting. We verify it really came from Google before trusting
  // any identity, then look up/create the user in SQLite.
  socket.on("register", async (idToken) => {
    try {
      const ticket = await googleClient.verifyIdToken({
        idToken,
        audience: GOOGLE_WEB_CLIENT_ID,
      });
      const payload = ticket.getPayload();

      if (!payload || !payload.sub) {
        throw new Error("Token payload missing required fields");
      }

      const user = findOrCreateUser({
        googleSub: payload.sub,
        email: payload.email || "unknown",
        displayName: payload.name || payload.email || "Unknown",
      });

      connectedUsers[socket.id] = user.display_name;
      console.log(`[register] verified ${user.display_name} <${user.email}> (${socket.id})`);
      broadcastUserList();
    } catch (err) {
      console.error(`[register] token verification failed: ${err.message}`);
      socket.emit("register-failed", { reason: "Invalid or expired sign-in. Please sign in again." });
    }
  });

  // --- Call request ---
  // Caller wants to call a specific user by their socket id.
  // payload: { toSocketId, fromUsername }
  socket.on("call-request", ({ toSocketId, fromUsername }) => {
    console.log(`[call-request] ${fromUsername} -> ${toSocketId}`);
    io.to(toSocketId).emit("call-request", {
      fromSocketId: socket.id,
      fromUsername,
    });
  });

  // --- Call accepted ---
  // payload: { toSocketId }  (toSocketId = original caller)
  socket.on("call-accepted", ({ toSocketId }) => {
    console.log(`[call-accepted] ${socket.id} accepted call from ${toSocketId}`);
    io.to(toSocketId).emit("call-accepted", { fromSocketId: socket.id });
  });

  // --- Call rejected ---
  // payload: { toSocketId }
  socket.on("call-rejected", ({ toSocketId }) => {
    console.log(`[call-rejected] ${socket.id} rejected call from ${toSocketId}`);
    io.to(toSocketId).emit("call-rejected", { fromSocketId: socket.id });
  });

  // --- WebRTC offer ---
  // payload: { toSocketId, offer }
  socket.on("offer", ({ toSocketId, offer }) => {
    console.log(`[offer] ${socket.id} -> ${toSocketId}`);
    io.to(toSocketId).emit("offer", { fromSocketId: socket.id, offer });
  });

  // --- WebRTC answer ---
  // payload: { toSocketId, answer }
  socket.on("answer", ({ toSocketId, answer }) => {
    console.log(`[answer] ${socket.id} -> ${toSocketId}`);
    io.to(toSocketId).emit("answer", { fromSocketId: socket.id, answer });
  });

  // --- ICE candidates ---
  // Exchanged repeatedly by both sides while negotiating the best network path.
  // payload: { toSocketId, candidate }
  socket.on("ice-candidate", ({ toSocketId, candidate }) => {
    io.to(toSocketId).emit("ice-candidate", {
      fromSocketId: socket.id,
      candidate,
    });
  });

  // --- Hangup ---
  // payload: { toSocketId }
  socket.on("hangup", ({ toSocketId }) => {
    console.log(`[hangup] ${socket.id} -> ${toSocketId}`);
    io.to(toSocketId).emit("hangup", { fromSocketId: socket.id });
  });

  // --- Disconnect ---
  // Fired automatically when a client closes the app / loses connection.
  socket.on("disconnect", () => {
    const username = connectedUsers[socket.id];
    console.log(`[disconnect] ${username || "unknown"} (${socket.id})`);
    delete connectedUsers[socket.id];
    broadcastUserList();
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Signaling server listening on port ${PORT}`);
});
