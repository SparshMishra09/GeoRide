import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/sharing_point.dart';
import '../services/sharing_service.dart';

class RidePreviewCard extends StatefulWidget {
  final SharingPoint ride;
  final Position userPosition;
  final VoidCallback onJoin;

  const RidePreviewCard({
    super.key,
    required this.ride,
    required this.userPosition,
    required this.onJoin,
  });

  @override
  State<RidePreviewCard> createState() => _RidePreviewCardState();
}

class _RidePreviewCardState extends State<RidePreviewCard> {
  bool _isJoining = false;
  bool _hasJoined = false;
  String _joinMessage = '';

  late double _distanceToRide;
  late String _distanceText;
  late bool _isHost;

  @override
  void initState() {
    super.initState();
    _isHost = widget.ride.creatorId == FirebaseAuth.instance.currentUser?.uid;
    _distanceToRide = SharingService.calculateDistanceToRide(widget.userPosition, widget.ride);
    _distanceText = SharingService.formatDistance(_distanceToRide);
    _hasJoined = widget.ride.passengers.contains(FirebaseAuth.instance.currentUser?.uid);
  }

  Future<void> _joinRide() async {
    setState(() {
      _isJoining = true;
      _joinMessage = 'Joining ride...';
    });

    final result = await SharingService().joinRide(widget.ride);

    if (!mounted) return;

    setState(() {
      _isJoining = false;
    });

    switch (result) {
      case 'success':
        setState(() => _hasJoined = true);
        Navigator.pop(context);
        widget.onJoin();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Joined ride! Head to the pickup point.'),
            backgroundColor: Colors.green,
          ),
        );
        break;
      case 'host_cannot_join_own':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot join your own ride.'),
            backgroundColor: Colors.orange,
          ),
        );
        break;
      case 'full':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This ride is full.'),
            backgroundColor: Colors.red,
          ),
        );
        break;
      case 'expired':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This ride has expired.'),
            backgroundColor: Colors.red,
          ),
        );
        break;
      case 'already_joined':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already joined this ride.'),
            backgroundColor: Colors.blue,
          ),
        );
        break;
      case 'already_in_ride':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are already in another ride.'),
            backgroundColor: Colors.orange,
          ),
        );
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to join ride. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _cancelRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B2321),
        title: const Text('Cancel Ride?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will cancel your ride and remove all passengers.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await SharingService().cancelRide(widget.ride);
      if (mounted) {
        Navigator.pop(context);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ride cancelled.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeRemaining = widget.ride.timeRemainingText;
    final isExpired = widget.ride.isExpired;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1B2321),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isHost ? 'Your Ride' : 'Ride Available!',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: widget.ride.seatsAvailable == widget.ride.totalSeats
                      ? Colors.green.withOpacity(0.2)
                      : widget.ride.seatsAvailable > 0
                          ? Colors.orange.withOpacity(0.2)
                          : Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.ride.seatsAvailable}/${widget.ride.totalSeats} seats',
                  style: TextStyle(
                    color: widget.ride.seatsAvailable == widget.ride.totalSeats
                        ? Colors.green
                        : widget.ride.seatsAvailable > 0
                            ? Colors.orange
                            : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // Destination
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on, color: Colors.white, size: 30),
            title: Text(
              widget.ride.destination,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Destination', style: TextStyle(color: Colors.grey)),
          ),
          const Divider(color: Colors.grey, height: 1),

          // Pickup Location (where host is)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_pin_circle, color: Colors.blueAccent, size: 30),
            title: const Text(
              'Host Location',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Go here to meet the host',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const Divider(color: Colors.grey, height: 1),

          // Distance & Time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Icon(Icons.straighten, color: Colors.greenAccent, size: 24),
                  const SizedBox(height: 5),
                  Text(
                    _distanceText,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Text('Distance', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              Column(
                children: [
                  const Icon(Icons.timer, color: Colors.orangeAccent, size: 24),
                  const SizedBox(height: 5),
                  Text(
                    timeRemaining,
                    style: TextStyle(
                      color: isExpired ? Colors.red : Colors.orangeAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('Time Left', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),

          // Action Buttons
          if (_isHost) ...[
            // Host view - show passengers and cancel option
            if (widget.ride.passengers.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Passengers:',
                      style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${widget.ride.passengers.length} passenger(s) joined',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: _cancelRide,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Cancel Ride', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ] else if (_hasJoined) ...[
            // Passenger already joined view
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You joined this ride!\nFollow the map to reach the host.',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isExpired || widget.ride.seatsAvailable <= 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red),
              ),
              child: Text(
                isExpired ? 'This ride has expired' : 'This ride is full',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ] else
            // Join button for non-host passengers
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: _isJoining ? null : _joinRide,
              child: _isJoining
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Join Ride',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
            ),
        ],
      ),
    );
  }
}
