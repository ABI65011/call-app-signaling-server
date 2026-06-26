// signaling_service.dart
//
// Handles two jobs:
// 1. Talking to the Node.js signaling server (Socket.IO) - register, presence,
//    call request/accept/reject, offer/answer/ICE relay, hangup.
// 2. Driving the actual WebRTC connection (RTCPeerConnection) so audio/video
//    can flow directly to the other device once signaling completes.
//
// This mirrors the exact event names used in server.js, so don't rename
// events here without changing the server too.

import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

// Public STUN server from Google - free, used to discover each peer's
// public-facing network address. This is NOT a TURN server (no relay
// fallback yet) - see project README for that tradeoff.
const Map<String, dynamic> _iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
  ],
};

enum CallState { idle, calling, ringing, inCall }

class SignalingService {
  final String serverUrl;
  final String username;

  IO.Socket? _socket;
  RTCPeerConnection? _peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;

  // The socket ID of whoever we're currently calling / in a call with.
  String? _remoteSocketId;
  String? get remoteSocketId => _remoteSocketId;

  // --- Callbacks the UI subscribes to ---
  // Each entry is a map: {'socketId': '...', 'username': '...'}
  void Function(List<Map<String, String>> users)? onUserListUpdated;
  void Function(String fromSocketId, String fromUsername)? onIncomingCall;
  void Function()? onCallAccepted;
  void Function()? onCallRejected;
  void Function(MediaStream stream)? onRemoteStream;
  void Function()? onCallEnded;
  void Function(String message)? onError;

  CallState callState = CallState.idle;

  SignalingService({required this.serverUrl, required this.username});

  // Connects to the signaling server and registers our username.
  void connect() {
    _socket = IO.io(
      serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNew()
          .build(),
    );

    _socket!.onConnect((_) {
      _socket!.emit('register', username);
    });

    _socket!.on('user-list', (data) {
      // data is now a List of {socketId, username} maps, not plain strings.
      // We filter ourselves out since you don't need to call yourself.
      final users = List<Map<String, dynamic>>.from(data)
          .map((u) => {
                'socketId': u['socketId'] as String,
                'username': u['username'] as String,
              })
          .where((u) => u['socketId'] != _socket!.id)
          .map((u) => <String, String>{
                'socketId': u['socketId']!,
                'username': u['username']!,
              })
          .toList();
      onUserListUpdated?.call(users);
    });

    _socket!.on('call-request', (data) {
      final fromSocketId = data['fromSocketId'] as String;
      final fromUsername = data['fromUsername'] as String;
      _remoteSocketId = fromSocketId;
      callState = CallState.ringing;
      onIncomingCall?.call(fromSocketId, fromUsername);
    });

    _socket!.on('call-accepted', (data) async {
      final fromSocketId = data['fromSocketId'] as String;
      _remoteSocketId = fromSocketId;
      callState = CallState.inCall;
      onCallAccepted?.call();
      await _createOfferAndSend();
    });

    _socket!.on('call-rejected', (data) {
      callState = CallState.idle;
      onCallRejected?.call();
    });

    _socket!.on('offer', (data) async {
      final fromSocketId = data['fromSocketId'] as String;
      final offer = data['offer'];
      _remoteSocketId = fromSocketId;
      await _handleOfferAndSendAnswer(offer);
    });

    _socket!.on('answer', (data) async {
      final answer = data['answer'];
      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
    });

    _socket!.on('ice-candidate', (data) async {
      final candidate = data['candidate'];
      if (candidate == null) return;
      await _peerConnection?.addCandidate(
        RTCIceCandidate(
          candidate['candidate'],
          candidate['sdpMid'],
          candidate['sdpMLineIndex'],
        ),
      );
    });

    _socket!.on('hangup', (_) {
      _endCallInternal();
      onCallEnded?.call();
    });

    _socket!.onConnectError((err) => onError?.call('Connection error: $err'));
    _socket!.onError((err) => onError?.call('Socket error: $err'));
  }

  // --- Outgoing actions, called by the UI ---

  void callUser(String toSocketId) {
    _remoteSocketId = toSocketId;
    callState = CallState.calling;
    _socket!.emit('call-request', {
      'toSocketId': toSocketId,
      'fromUsername': username,
    });
  }

  Future<void> acceptCall() async {
    if (_remoteSocketId == null) return;
    callState = CallState.inCall;
    await _setupLocalMedia();
    _socket!.emit('call-accepted', {'toSocketId': _remoteSocketId});
  }

  void rejectCall() {
    if (_remoteSocketId == null) return;
    _socket!.emit('call-rejected', {'toSocketId': _remoteSocketId});
    _remoteSocketId = null;
    callState = CallState.idle;
  }

  void hangUp() {
    if (_remoteSocketId != null) {
      _socket!.emit('hangup', {'toSocketId': _remoteSocketId});
    }
    _endCallInternal();
  }

  // --- WebRTC internals ---

  Future<void> _setupLocalMedia() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'width': 640,
        'height': 480,
      },
    });
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final pc = await createPeerConnection(_iceServers);

    // Send our ICE candidates to the other side as they're discovered.
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (_remoteSocketId == null) return;
      _socket!.emit('ice-candidate', {
        'toSocketId': _remoteSocketId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    // When the remote side's media arrives, hand it to the UI.
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        onRemoteStream?.call(remoteStream!);
      }
    };

    // Attach our own local tracks (camera/mic) so the other side receives them.
    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        await pc.addTrack(track, localStream!);
      }
    }

    return pc;
  }

  // Caller side: after the callee accepts, build an SDP offer and send it.
  Future<void> _createOfferAndSend() async {
    await _setupLocalMedia();
    _peerConnection = await _createPeerConnection();

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _socket!.emit('offer', {
      'toSocketId': _remoteSocketId,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });
  }

  // Callee side: received an offer, build an answer and send it back.
  Future<void> _handleOfferAndSendAnswer(dynamic offer) async {
    _peerConnection = await _createPeerConnection();

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _socket!.emit('answer', {
      'toSocketId': _remoteSocketId,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  void _endCallInternal() {
    _peerConnection?.close();
    _peerConnection = null;
    localStream?.getTracks().forEach((track) => track.stop());
    localStream?.dispose();
    localStream = null;
    remoteStream = null;
    _remoteSocketId = null;
    callState = CallState.idle;
  }

  void dispose() {
    _endCallInternal();
    _socket?.dispose();
  }
}
