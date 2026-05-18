const { io } = require("socket.io-client");

const BACKEND_URL = process.env.BACKEND_URL || "http://localhost:3000";
const ROOM_ID = "runtime_validation_room";

function waitForEvent(socket, eventName, timeoutMs = 8000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off(eventName, onEvent);
      reject(new Error(`Timed out waiting for ${eventName}`));
    }, timeoutMs);

    function onEvent(payload) {
      clearTimeout(timer);
      socket.off(eventName, onEvent);
      resolve(payload);
    }

    socket.on(eventName, onEvent);
  });
}

function connectClient(alias, userId) {
  const socket = io(BACKEND_URL, {
    transports: ["websocket"],
    reconnection: false,
    timeout: 8000,
  });

  const connected = waitForEvent(socket, "connect");

  socket.on("connect", () => {
    socket.emit("join-room", { roomId: ROOM_ID, alias, userId });
  });

  return { socket, connected };
}

async function main() {
  const results = [];
  const clientA = connectClient("alpha_client", "alpha_user");
  const clientB = connectClient("bravo_client", "bravo_user");

  await Promise.all([clientA.connected, clientB.connected]);
  results.push(["socket connect", "PASS", "both clients connected"]);

  const aWaiting = waitForEvent(clientA.socket, "matchmaking-status");
  clientA.socket.emit("matchmaking-join", { alias: "alpha_client" });
  const aWaitingPayload = await aWaiting;
  results.push([
    "matchmaking join",
    aWaitingPayload.status === "waiting" ? "PASS" : "FAIL",
    JSON.stringify(aWaitingPayload),
  ]);

  const aMatched = waitForEvent(clientA.socket, "matched");
  const bMatched = waitForEvent(clientB.socket, "matched");
  clientB.socket.emit("matchmaking-join", { alias: "bravo_client" });
  const [matchA, matchB] = await Promise.all([aMatched, bMatched]);
  results.push([
    "matchmaking pair",
    matchA.roomId && matchB.roomId && matchA.roomId === matchB.roomId
      ? "PASS"
      : "FAIL",
    JSON.stringify({ matchA, matchB }),
  ]);

  const dupWaiting = waitForEvent(clientA.socket, "matchmaking-status");
  clientA.socket.emit("matchmaking-join", { alias: "alpha_client" });
  const dupWaitingPayload = await dupWaiting;
  results.push([
    "duplicate join handling",
    dupWaitingPayload.status === "waiting" ? "PASS" : "FAIL",
    JSON.stringify(dupWaitingPayload),
  ]);

  const bLeft = waitForEvent(clientB.socket, "matchmaking-status");
  clientB.socket.emit("matchmaking-leave", {});
  const bLeftPayload = await bLeft;
  results.push([
    "matchmaking leave",
    bLeftPayload.status === "left" ? "PASS" : "FAIL",
    JSON.stringify(bLeftPayload),
  ]);

  const bRejoinedMatched = waitForEvent(clientB.socket, "matched");
  const aRejoinedMatched = waitForEvent(clientA.socket, "matched");
  clientB.socket.emit("matchmaking-join", { alias: "bravo_client" });
  clientA.socket.emit("matchmaking-join", { alias: "alpha_client" });
  const [rejoinA, rejoinB] = await Promise.all([
    aRejoinedMatched,
    bRejoinedMatched,
  ]);
  const roomId = rejoinA.roomId || rejoinB.roomId;
  const aAlias = rejoinA.yourAlias;
  const bAlias = rejoinB.yourAlias;
  results.push([
    "rejoin pair",
    roomId ? "PASS" : "FAIL",
    JSON.stringify({ rejoinA, rejoinB }),
  ]);

  const offerSeen = waitForEvent(clientB.socket, "webrtc-signal");
  clientA.socket.emit("webrtc-signal", {
    roomId,
    type: "offer",
    sdp: "fake-offer-sdp",
    senderAlias: aAlias,
  });
  const offerPayload = await offerSeen;
  results.push([
    "webrtc offer",
    offerPayload.type === "offer" ? "PASS" : "FAIL",
    JSON.stringify(offerPayload),
  ]);

  const answerSeen = waitForEvent(clientA.socket, "webrtc-signal");
  clientB.socket.emit("webrtc-signal", {
    roomId,
    type: "answer",
    sdp: "fake-answer-sdp",
    senderAlias: bAlias,
  });
  const answerPayload = await answerSeen;
  results.push([
    "webrtc answer",
    answerPayload.type === "answer" ? "PASS" : "FAIL",
    JSON.stringify(answerPayload),
  ]);

  const iceSeen = waitForEvent(clientB.socket, "webrtc-signal");
  clientA.socket.emit("webrtc-signal", {
    roomId,
    type: "candidate",
    candidate: {
      candidate: "candidate:1 1 udp 2122260223 127.0.0.1 12345 typ host",
    },
    senderAlias: aAlias,
  });
  const icePayload = await iceSeen;
  results.push([
    "ice candidate",
    icePayload.type === "candidate" ? "PASS" : "FAIL",
    JSON.stringify(icePayload),
  ]);

  const incomingCallSeen = waitForEvent(clientB.socket, "incoming-call");
  const callStateRingingSeen = waitForEvent(clientA.socket, "call-state");
  clientA.socket.emit("call-initiate", {
    roomId,
    recipientAlias: "bravo_client",
    type: "audio",
    callType: "audio",
  });
  const incomingCallPayload = await incomingCallSeen;
  const callStateRingingPayload = await callStateRingingSeen;
  results.push([
    "call initiate",
    incomingCallPayload.roomId === roomId &&
    callStateRingingPayload.state === "ringing"
      ? "PASS"
      : "FAIL",
    JSON.stringify({ incomingCallPayload, callStateRingingPayload }),
  ]);

  const callConnectedSeen = waitForEvent(clientA.socket, "call-state");
  const callConnectedPeerSeen = waitForEvent(clientB.socket, "call-state");
  clientB.socket.emit("call-accept", { roomId });
  const [callConnectedPayloadA, callConnectedPayloadB] = await Promise.all([
    callConnectedSeen,
    callConnectedPeerSeen,
  ]);
  results.push([
    "call accept",
    callConnectedPayloadA.state === "connected" &&
    callConnectedPayloadB.state === "connected"
      ? "PASS"
      : "FAIL",
    JSON.stringify({ callConnectedPayloadA, callConnectedPayloadB }),
  ]);

  const callEndedSeen = waitForEvent(clientB.socket, "call-ended");
  clientA.socket.emit("call-ended", {
    roomId,
    peerAlias: bAlias,
    type: "audio",
    durationSeconds: 12,
  });
  const callEndedPayload = await callEndedSeen;
  results.push([
    "call ended cleanup",
    callEndedPayload.roomId === roomId ? "PASS" : "FAIL",
    JSON.stringify(callEndedPayload),
  ]);

  clientB.socket.disconnect();
  const clientBReconnect = connectClient("bravo_client", "bravo_user");
  await clientBReconnect.connected;
  results.push(["reconnect", "PASS", "clientB reconnected as new socket"]);

  clientA.socket.disconnect();
  clientBReconnect.socket.disconnect();

  for (const [label, status, evidence] of results) {
    // eslint-disable-next-line no-console
    console.log(`${label}\t${status}\t${evidence}`);
  }

  const failed = results.filter(([, status]) => status !== "PASS");
  if (failed.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error(error);
  process.exit(1);
});
