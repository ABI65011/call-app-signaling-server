// home_screen.dart
//
// Shows the list of online users (from the signaling server) with a call
// button next to each. Also listens for incoming calls and shows a simple
// accept/reject dialog when one arrives.

import 'package:flutter/material.dart';
import 'signaling_service.dart';
import 'call_screen.dart';

class HomeScreen extends StatefulWidget {
  final SignalingService signaling;

  const HomeScreen({super.key, required this.signaling});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, String>> _onlineUsers = [];
  String? _statusMessage;

  @override
  void initState() {
    super.initState();

    widget.signaling.onUserListUpdated = (users) {
      setState(() => _onlineUsers = users);
    };

    widget.signaling.onIncomingCall = (fromSocketId, fromUsername) {
      _showIncomingCallDialog(fromSocketId, fromUsername);
    };

    widget.signaling.onError = (message) {
      setState(() => _statusMessage = message);
    };

    widget.signaling.connect();
  }

  void _showIncomingCallDialog(String fromSocketId, String fromUsername) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Incoming call'),
        content: Text('$fromUsername is calling you.'),
        actions: [
          TextButton(
            onPressed: () {
              widget.signaling.rejectCall();
              Navigator.of(context).pop();
            },
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await widget.signaling.acceptCall();
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CallScreen(signaling: widget.signaling),
                ),
              );
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  void _callUser(String socketId) {
    widget.signaling.callUser(socketId);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CallScreen(signaling: widget.signaling)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Signed in as ${widget.signaling.username}'),
      ),
      body: Column(
        children: [
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.all(8),
              child: Text(_statusMessage!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _onlineUsers.isEmpty
                ? const Center(child: Text('No one else is online yet.'))
                : ListView.builder(
                    itemCount: _onlineUsers.length,
                    itemBuilder: (context, index) {
                      final user = _onlineUsers[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(user['username']!),
                        trailing: IconButton(
                          icon: const Icon(Icons.call, color: Colors.green),
                          onPressed: () => _callUser(user['socketId']!),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
