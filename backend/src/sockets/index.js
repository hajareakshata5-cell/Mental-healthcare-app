const { Server } = require("socket.io");
const ChatMessage = require("../models/ChatMessage");
const CallLog = require("../models/CallLog");
const User = require("../models/User");
const onlineUsers = new Map();
const matchmakingQueue = [];
const crypto = require("crypto");

function sanitizeAlias(value, fallback = "anon") {
  const safe = String(value || fallback)
    .replace(/[^a-zA-Z0-9_\-]/g, "")
    .slice(0, 32);
  return safe || fallback;
}

function sanitizeBody(value, maxLength = 3000) {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim().replace(/\0/g, "").slice(0, maxLength);
}

function removeQueueEntries(predicate) {
  for (let index = matchmakingQueue.length - 1; index >= 0; index -= 1) {
    if (predicate(matchmakingQueue[index])) {
      matchmakingQueue.splice(index, 1);
    }
  }
}

function emitToAlias(io, alias, event, payload) {
  const target = Array.from(onlineUsers.values()).find(
    (entry) => entry.alias === alias,
  );

  if (target) {
    io.to(target.socketId).emit(event, payload);
  }
}

function registerSocketHandlers(server, allowedOrigins) {
  const io = new Server(server, {
    cors: {
      origin: allowedOrigins,
      credentials: true,
    },
  });

  io.on("connection", (socket) => {
    socket.on("join-room", ({ roomId, alias, userId }) => {
      const safeRoomId = sanitizeAlias(roomId, socket.id);
      const safeAlias = sanitizeAlias(alias, `anon_${socket.id.slice(0, 6)}`);
      const safeUserId = sanitizeAlias(userId, socket.id);
      console.log("[socket] join-room", {
  userId: safeUserId,
  alias: safeAlias,
  socketId: socket.id,
});

      removeQueueEntries(
        (entry) => entry.userId === safeUserId || entry.socketId === socket.id,
      );

      socket.join(safeRoomId);
      socket.data.alias = safeAlias;
      socket.data.userId = safeUserId;
      onlineUsers.set(socket.data.userId, {
        id: socket.data.userId,
        alias: safeAlias,
        socketId: socket.id,
        status: "online",
        lastSeenAt: new Date().toISOString(),
      });
      if (socket.data.userId) {
      User.findByIdAndUpdate(socket.data.userId, {
      isOnlineForMatching: true,
      lastSeenForMatchingAt: new Date(),
     }).catch(console.error);
     console.log("[socket] online-for-matching true", safeUserId);
    }
      io.emit("online-users", Array.from(onlineUsers.values()));
      io.to(safeRoomId).emit("presence", { alias: safeAlias, state: "joined" });
    });

    socket.on("chat-message", async (payload) => {
      const body = sanitizeBody(payload?.body);
      if (!payload?.roomId || !body) {
        return;
      }

      const row = await ChatMessage.create({
        roomId: payload.roomId,
        senderAlias: payload.senderAlias,
        recipientAlias: payload.recipientAlias,
        body,
        moderated: { flagged: false, reasons: [] },
      });

      io.to(payload.roomId).emit("chat-message", {
        id: String(row._id),
        senderAlias: row.senderAlias,
        body: row.body,
        createdAt: row.createdAt,
      });
    });

    // Matchmaking: join queue to be paired anonymously
    socket.on("matchmaking-join", (payload = {}) => {
      removeQueueEntries(
        (entry) =>
          entry.userId === socket.data.userId || entry.socketId === socket.id,
      );

      const entry = {
        socketId: socket.id,
        alias: sanitizeAlias(payload.alias, `anon_${socket.id.slice(0, 6)}`),
        userId: socket.data.userId || null,
        joinedAt: Date.now(),
      };

      // Avoid duplicates
      const exists = matchmakingQueue.find((q) => q.socketId === socket.id);
      if (!exists) matchmakingQueue.push(entry);

      // If there is another waiting user, pair them
      if (matchmakingQueue.length >= 2) {
        // take first two
        const a = matchmakingQueue.shift();
        const b = matchmakingQueue.shift();

        const roomId = `anon_${crypto.randomBytes(6).toString("hex")}`;

        // assign anonymous aliases
        const aliasA = `Support_${Math.floor(Math.random() * 9000) + 1000}`;
        const aliasB = `Support_${Math.floor(Math.random() * 9000) + 1000}`;

        // notify both sockets
        try {
          io.to(a.socketId).emit("matched", {
            roomId,
            yourAlias: aliasA,
            peerAlias: aliasB,
            anonymous: true,
          });
        } catch (err) {}

        try {
          io.to(b.socketId).emit("matched", {
            roomId,
            yourAlias: aliasB,
            peerAlias: aliasA,
            anonymous: true,
          });
        } catch (err) {}

        // Join both sockets to the room (if still connected)
        const sa = io.sockets.sockets.get(a.socketId);
        const sb = io.sockets.sockets.get(b.socketId);
        if (sa) sa.join(roomId);
        if (sb) sb.join(roomId);

        io.to(roomId).emit("presence", { state: "matched", roomId });
      } else {
        io.to(socket.id).emit("matchmaking-status", { status: "waiting" });
      }
    });

    socket.on("matchmaking-leave", () => {
      const idx = matchmakingQueue.findIndex((q) => q.socketId === socket.id);
      if (idx >= 0) matchmakingQueue.splice(idx, 1);
      io.to(socket.id).emit("matchmaking-status", { status: "left" });
    });

    socket.on("webrtc-signal", (payload) => {
      if (payload.recipientAlias) {
        emitToAlias(io, payload.recipientAlias, "webrtc-signal", payload);
        return;
      }

      socket.to(payload.roomId).emit("webrtc-signal", payload);
    });

    socket.on("call-initiate", async (payload) => {
      try {
        // Enforce free-tier call limit (2 free calls)
        if (socket.data.userId) {
          try {
            const used = await CallLog.countDocuments({
              userId: socket.data.userId,
              isFreeTier: true,
            });
            if (used >= 2) {
              io.to(socket.id).emit("premium-required", {
                message:
                  "Free call limit reached. Upgrade to Premium to continue.",
                freeCallsUsed: used,
                freeCallsLimit: 2,
              });
              return;
            }
          } catch (err) {
            // ignore DB check failure and allow call to proceed
          }
        }

        emitToAlias(io, payload.recipientAlias, "incoming-call", {
          ...payload,
          callerAlias: socket.data.alias,
        });
        io.to(payload.roomId).emit("call-state", {
          roomId: payload.roomId,
          state: "ringing",
          callerAlias: socket.data.alias,
          recipientAlias: payload.recipientAlias,
        });
      } catch (err) {
        console.error("call-initiate error", err);
      }
    });

    socket.on("call-accept", (payload) => {
      io.to(payload.roomId).emit("call-state", {
        roomId: payload.roomId,
        state: "connected",
        recipientAlias: socket.data.alias,
      });
    });

    socket.on("call-decline", (payload) => {
      io.to(payload.roomId).emit("call-state", {
        roomId: payload.roomId,
        state: "ended",
        recipientAlias: socket.data.alias,
      });
    });

    socket.on("dm-message", async (payload) => {
      const body = sanitizeBody(payload?.body);
      if (!body) {
        return;
      }

      const row = await ChatMessage.create({
        roomId: payload.roomId,
        senderAlias: payload.senderAlias,
        recipientAlias: payload.recipientAlias,
        body,
        moderated: { flagged: false, reasons: [] },
      });

      const outbound = {
        id: String(row._id),
        senderAlias: row.senderAlias,
        recipientAlias: row.recipientAlias,
        body: row.body,
        createdAt: row.createdAt,
      };

      if (payload.roomId) {
        io.to(payload.roomId).emit("dm-message", outbound);
        return;
      }

      if (payload.recipientAlias) {
        emitToAlias(io, payload.recipientAlias, "dm-message", outbound);
      }

      io.to(socket.id).emit("dm-message", outbound);
    });

    socket.on("typing", (payload) => {
      try {
        if (!payload?.roomId) return;
        socket.to(payload.roomId).emit("typing", {
          senderAlias: socket.data.alias,
          typing: true,
        });
      } catch (err) {}
    });

    socket.on("stop-typing", (payload) => {
      try {
        if (!payload?.roomId) return;
        socket.to(payload.roomId).emit("typing", {
          senderAlias: socket.data.alias,
          typing: false,
        });
      } catch (err) {}
    });

    socket.on("call-state", (payload) => {
      if (!payload?.roomId) return;
      socket.to(payload.roomId).emit("call-state", payload);
    });

    socket.on("call-ended", async (payload) => {
      if (payload.userId) {
        await CallLog.create({
          userId: payload.userId,
          peerAlias: payload.peerAlias,
          type: payload.type || "audio",
          durationSeconds: payload.durationSeconds || 0,
          status: "ended",
          isFreeTier: !!payload.isFreeTier,
        });
      }
      io.to(payload.roomId).emit("call-ended", payload);
    });

    socket.on("disconnect", () => {
      if (socket.data.userId) {
        User.findByIdAndUpdate(socket.data.userId, {
  isOnlineForMatching: false,
  lastSeenForMatchingAt: new Date(),
}).catch(console.error);
console.log(
  "[socket] online-for-matching false",
  socket.data.userId,
);
        const current = onlineUsers.get(socket.data.userId);
        if (current) {
          onlineUsers.set(socket.data.userId, {
            ...current,
            status: "offline",
            socketId: socket.id,
            lastSeenAt: new Date().toISOString(),
          });
        }
        io.emit("online-users", Array.from(onlineUsers.values()));
      }

      removeQueueEntries(
        (entry) =>
          entry.socketId === socket.id || entry.userId === socket.data.userId,
      );
    });
  });

  return io;
}

module.exports = { registerSocketHandlers };
