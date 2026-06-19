// Simulates two clients (Caller + Callee) going through the entire
// signaling flow, to verify the server correctly relays every event.
const { io } = require("socket.io-client");

const SERVER_URL = "http://localhost:3000";

function log(who, msg, data) {
  console.log(`[${who}] ${msg}`, data !== undefined ? data : "");
}

const caller = io(SERVER_URL);
const callee = io(SERVER_URL);

let calleeSocketId = null;
let callerSocketId = null;
let testPassed = {
  registered: false,
  callRequestReceived: false,
  callAccepted: false,
  offerReceived: false,
  answerReceived: false,
  iceExchanged: false,
  hangupReceived: false,
};

caller.on("connect", () => {
  callerSocketId = caller.id;
  log("CALLER", "connected as", caller.id);
  caller.emit("register", "Jedidiah-Android");
});

callee.on("connect", () => {
  calleeSocketId = callee.id;
  log("CALLEE", "connected as", callee.id);
  callee.emit("register", "Friend-Linux");
});

callee.on("user-list", (users) => {
  log("CALLEE", "user-list updated:", users);
  // Once both are registered, caller initiates a call to callee.
  if (users.length === 2 && !testPassed.registered) {
    testPassed.registered = true;
    setTimeout(() => {
      log("CALLER", "sending call-request to", calleeSocketId);
      caller.emit("call-request", {
        toSocketId: calleeSocketId,
        fromUsername: "Jedidiah-Android",
      });
    }, 200);
  }
});

callee.on("call-request", ({ fromSocketId, fromUsername }) => {
  testPassed.callRequestReceived = true;
  log("CALLEE", `incoming call from ${fromUsername} (${fromSocketId})`);
  // Accept the call
  callee.emit("call-accepted", { toSocketId: fromSocketId });
});

caller.on("call-accepted", ({ fromSocketId }) => {
  testPassed.callAccepted = true;
  log("CALLER", "call was accepted by", fromSocketId);
  // Send a fake SDP offer
  caller.emit("offer", {
    toSocketId: fromSocketId,
    offer: { type: "offer", sdp: "fake-sdp-offer-data" },
  });
});

callee.on("offer", ({ fromSocketId, offer }) => {
  testPassed.offerReceived = true;
  log("CALLEE", "received offer:", offer);
  // Send back a fake SDP answer
  callee.emit("answer", {
    toSocketId: fromSocketId,
    answer: { type: "answer", sdp: "fake-sdp-answer-data" },
  });
  // Also send a fake ICE candidate
  callee.emit("ice-candidate", {
    toSocketId: fromSocketId,
    candidate: { candidate: "fake-ice-candidate-from-callee" },
  });
});

caller.on("answer", ({ fromSocketId, answer }) => {
  testPassed.answerReceived = true;
  log("CALLER", "received answer:", answer);
});

caller.on("ice-candidate", ({ fromSocketId, candidate }) => {
  testPassed.iceExchanged = true;
  log("CALLER", "received ICE candidate:", candidate);
  // Caller sends hangup shortly after, to test that path too
  setTimeout(() => {
    log("CALLER", "sending hangup");
    caller.emit("hangup", { toSocketId: fromSocketId });
  }, 300);
});

callee.on("hangup", ({ fromSocketId }) => {
  testPassed.hangupReceived = true;
  log("CALLEE", "received hangup from", fromSocketId);

  // Final report
  setTimeout(() => {
    console.log("\n=== TEST RESULTS ===");
    let allPassed = true;
    for (const [key, value] of Object.entries(testPassed)) {
      console.log(`${value ? "PASS" : "FAIL"} - ${key}`);
      if (!value) allPassed = false;
    }
    console.log(allPassed ? "\nALL CHECKS PASSED" : "\nSOME CHECKS FAILED");
    process.exit(allPassed ? 0 : 1);
  }, 200);
});

// Safety timeout in case something hangs
setTimeout(() => {
  console.log("\nTEST TIMED OUT. Partial results:", testPassed);
  process.exit(1);
}, 8000);
