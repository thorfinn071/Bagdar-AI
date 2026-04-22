import 'package:flutter/material.dart';

import '../models/strings.dart';
import '../services/waypoint_service.dart';

class WaypointSheet extends StatefulWidget {
  final WaypointService waypointService;
  final void Function(String name)? onDeleted;

  const WaypointSheet({
    super.key,
    required this.waypointService,
    this.onDeleted,
  });

  @override
  State<WaypointSheet> createState() => _WaypointSheetState();
}

class _WaypointSheetState extends State<WaypointSheet> {
  late List<Waypoint> _waypoints;

  @override
  void initState() {
    super.initState();
    _waypoints = List.of(widget.waypointService.waypoints);
  }

  Future<void> _delete(Waypoint wp) async {
    await widget.waypointService.delete(wp.id);
    widget.onDeleted?.call(wp.id);
    if (mounted) {
      setState(() {
        _waypoints.removeWhere((w) => w.id == wp.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, scrollCtrl) => Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.place, color: Colors.cyanAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  S.get('waypoint_name_prompt'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_waypoints.length}',
                  style: const TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          Expanded(
            child: _waypoints.isEmpty
                ? Center(
                    child: Text(
                      S.get('waypoint_none'),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 15,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: _waypoints.length,
                    itemBuilder: (_, i) => _WaypointTile(
                      waypoint: _waypoints[i],
                      onDelete: () => _delete(_waypoints[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _WaypointTile extends StatelessWidget {
  final Waypoint waypoint;
  final VoidCallback onDelete;

  const _WaypointTile({required this.waypoint, required this.onDelete});

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.'
        '${d.year}  '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${waypoint.name}, ${_formatDate(waypoint.created)}',
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: const Icon(
          Icons.location_on,
          color: Colors.orangeAccent,
          size: 22,
        ),
        title: Text(
          waypoint.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${_formatDate(waypoint.created)}\n'
          '${waypoint.lat.toStringAsFixed(5)}, '
          '${waypoint.lng.toStringAsFixed(5)}',
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        isThreeLine: true,
        trailing: Semantics(
          label: '${S.get('waypoint_deleted')} ${waypoint.name}',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: S.get('waypoint_deleted'),
            onPressed: () => _confirmDelete(context),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(waypoint.name, style: const TextStyle(color: Colors.white)),
        content: Text(
          '${S.get('waypoint_deleted')}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              S.get('cancel'),
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, true);
              onDelete();
            },
            child: Text(
              S.get('waypoint_deleted'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}
