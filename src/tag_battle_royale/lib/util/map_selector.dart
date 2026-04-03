import 'package:flutter/material.dart';

import '../util/map_file_handler.dart';
import '../widgets/map_viewer.dart';
import '../widgets/google_maps_viewer.dart';

/// Map browser that lets the host view and select a map for the game.
/// Used by both online and offline lobbies.
///
/// [canCreateMaps] controls whether the "Create New Map" option is shown.
/// Online hosts can create maps, offline hosts can only select existing ones.
class MapSelector extends StatefulWidget {
  const MapSelector({
    super.key,
    required this.onMapSelected,
    this.selectedMapName,
    this.selectedMapId,
    this.canCreateMaps = false,
  });

  final void Function(MapFile? map) onMapSelected;
  final String? selectedMapName;
  final String? selectedMapId;
  final bool canCreateMaps;

  @override
  State<MapSelector> createState() => _MapSelectorState();
}

class _MapSelectorState extends State<MapSelector> {
  late Future<List<MapFile>> _mapsFuture;

  @override
  void initState() {
    super.initState();
    _reloadMaps();
  }

  void _reloadMaps() {
    _mapsFuture = getMaps();
  }

  /// Open the map viewer with a "Select Map" button.
  Future<void> _viewAndSelect(MapFile map) async {
    final selected = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MapViewer(
          map: map,
          showSelectButton: true,
        ),
      ),
    );

    if (selected == true) {
      widget.onMapSelected(map);
    }
  }

  /// Navigate to map creation. Auto-select the new map.
  Future<void> _createNewMap() async {
    final shouldReload = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GoogleMaps()),
    );

    if (shouldReload == true) {
      setState(() => _reloadMaps());
      // Auto-select the newest map (last in the list)
      final maps = await getMaps();
      if (maps.isNotEmpty) {
        widget.onMapSelected(maps.last);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Currently selected map
        if (widget.selectedMapId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selected: ${widget.selectedMapName}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Create new map (online only)
        if (widget.canCreateMaps)
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text("Create New Map"),
            onTap: _createNewMap,
          ),

        const Divider(height: 1),

        // Map list
        Expanded(
          child: FutureBuilder<List<MapFile>>(
            future: _mapsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(child: Text("Error loading maps"));
              }
              final maps = snapshot.data ?? [];
              if (maps.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.map_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No maps yet',
                          style: TextStyle(color: Colors.grey)),
                      if (widget.canCreateMaps) ...[
                        const SizedBox(height: 8),
                        const Text('Create one to get started',
                            style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ],
                  ),
                );
              }
              return ListView.builder(
                itemCount: maps.length,
                itemBuilder: (context, index) {
                  final map = maps[index];
                  final isSelected = map.id == widget.selectedMapId;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.check_circle : Icons.map,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      map.mapName,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: isSelected ? const Text('Selected') : null,
                    onTap: () => _viewAndSelect(map),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}