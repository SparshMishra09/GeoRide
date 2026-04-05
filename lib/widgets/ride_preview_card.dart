import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/sharing_point.dart';
import '../services/sharing_service.dart';

class RidePreviewCard extends StatefulWidget {
  final SharingPoint ride;
  final VoidCallback onJoin;

  const RidePreviewCard({super.key, required this.ride, required this.onJoin});

  @override
  State<RidePreviewCard> createState() => _RidePreviewCardState();
}

class _RidePreviewCardState extends State<RidePreviewCard> {
  bool _isJoining = false;
  bool _hasJoined = false;
  String? _distanceText;

  @override
  void initState() {
    super.initState();
    _calculateDistance();
  }

  Future<void> _calculateDistance() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        widget.ride.lat,
        widget.ride.lng,
      );
      
      if (mounted) {
        setState(() {
          if (distance < 1000) {
            _distanceText = '${distance.toStringAsFixed(0)}m away';
          } else {
            _distanceText = '${(distance / 1000).toStringAsFixed(1)}km away';
          }
        });
      }
    } catch (e) {
      debugPrint('Error calculating distance: $e');
    }
  }

  Future<void> _joinRide() async {
    setState(() => _isJoining = true);

    try {
      bool success = await SharingService().joinRide(widget.ride);

      if (mounted) {
        setState(() {
          _isJoining = false;
          _hasJoined = success;
        });

        Navigator.pop(context); // close bottom sheet
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? "Joined Ride! Heading to pickup point..." : "Could not join ride. It might be full."),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
        
        if (success) {
          widget.onJoin();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isJoining = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _imNear() async {
    try {
      // Update the sharing point to notify the host you're near
      await SharingService().markPassengerNear(widget.ride);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Host notified that you\'re nearby!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1B2321),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               const Text("Ride Available!", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 20)),
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                 decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                 child: Text("${widget.ride.seatsAvailable} seats left", style: const TextStyle(color: Colors.blueAccent)),
               )
            ],
          ),
          const SizedBox(height: 15),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on, color: Colors.white),
            title: Text(widget.ride.destination, style: const TextStyle(color: Colors.white, fontSize: 18)),
            subtitle: Text(_distanceText ?? "Calculating distance...", style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(height: 10),
          if (_hasJoined) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "You've joined this ride! Head to the pickup point.",
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              onPressed: _imNear,
              icon: const Icon(Icons.near_me),
              label: const Text("I'm Near", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ] else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                 backgroundColor: Colors.greenAccent,
                 foregroundColor: Colors.black,
                 padding: const EdgeInsets.symmetric(vertical: 15),
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              onPressed: _isJoining ? null : _joinRide,
              child: _isJoining
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text("Join Ride", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            )
        ],
      ),
    );
  }
}
