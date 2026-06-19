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
  const usernames = Object.values(connectedUsers);
  io.emit("user-list", usernames);
}

io.on("connection", (socket) => {
  console.log(`[connect] socket ${socket.id} connected`);

  // --- Registration ---
  // Client sends their chosen display name right after connecting.
  socket.on("register", (username) => {
    connectedUsers[socket.id] = username;
    console.log(`[register] ${username} (${socket.id})`);
    broadcastUserList();
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
