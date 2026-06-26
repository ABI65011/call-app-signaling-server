// call_screen.dart
//
// Shows local + remote video, and basic call controls (mute, hang up).
// Handles both "calling" (waiting for the other side to accept) and
// "in call" states.

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_service.dart';

class CallScreen extends StatefulWidget {
  final SignalingService signaling;

  const CallScreen({super.key, required this.signaling});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _micMuted = false;
  String _statusText = 'Calling...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // If we're the callee, local media was already requested in
    // acceptCall(). If we're the caller, it gets requested once the
    // call is accepted (see signaling_service.dart _createOfferAndSend).
    // Either way, attach whatever's available now, and also listen for
    // it becoming available shortly after.
    _attachLocalStreamIfReady();

    widget.signaling.onCallAccepted = () {
      setState(() => _statusText = 'Connecting...');
      // Local stream becomes available shortly after acceptance for the
      // caller side; poll briefly until it's attached.
      _attachLocalStreamIfReady();
    };

    widget.signaling.onRemoteStream = (stream) {
      setState(() {
        _remoteRenderer.srcObject = stream;
        _statusText = 'In call';
      });
    };

    widget.signaling.onCallRejected = () {
      setState(() => _statusText = 'Call declined');
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.of(context).pop();
      });
    };

    widget.signaling.onCallEnded = () {
      if (mounted) Navigator.of(context).pop();
    };
  }

  void _attachLocalStreamIfReady() {
    final stream = widget.signaling.localStream;
    if (stream != null) {
      setState(() => _localRenderer.srcObject = stream);
    } else {
      // Local media may not be ready the instant this screen opens
      // (e.g. caller side waits for call-accepted). Check again shortly.
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _localRenderer.srcObject == null) {
          _attachLocalStreamIfReady();
        }
      });
    }
  }

  void _toggleMic() {
    final audioTracks = widget.signaling.localStream?.getAudioTracks();
    if (audioTracks == null || audioTracks.isEmpty) return;
    setState(() {
      _micMuted = !_micMuted;
      for (var track in audioTracks) {
        track.enabled = !_micMuted;
      }
    });
  }

  void _hangUp() {
    widget.signaling.hangUp();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote video fills the screen.
          Positioned.fill(
            child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
          ),

          // Local preview, small box top-right.
          Positioned(
            top: 24,
            right: 24,
            width: 160,
            height: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: RTCVideoView(_localRenderer, mirror: true),
            ),
          ),

          // Status text top-left.
          Positioned(
            top: 24,
            left: 24,
            child: Text(
              _statusText,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),

          // Controls at the bottom.
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  heroTag: 'mic',
                  backgroundColor: _micMuted ? Colors.grey : Colors.white,
                  onPressed: _toggleMic,
                  child: Icon(_micMuted ? Icons.mic_off : Icons.mic, color: Colors.black),
                ),
                const SizedBox(width: 24),
                FloatingActionButton(
                  heroTag: 'hangup',
                  backgroundColor: Colors.red,
                  onPressed: _hangUp,
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
