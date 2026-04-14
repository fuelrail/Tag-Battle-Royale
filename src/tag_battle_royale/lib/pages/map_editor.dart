import 'package:flutter/material.dart';
import 'package:tag_battle_royale/util/player.dart';

import 'example_game.dart';
import '../widgets/map_viewer.dart';
import '../util/map_file_handler.dart';
import '../widgets/google_maps_viewer.dart';

class MapEditor extends StatefulWidget {
  const MapEditor({super.key});

  @override
  State<MapEditor> createState() => _MapEditorState();
}

class _MapEditorState extends State<MapEditor> {
  late Future<List<MapFile>> _mapsFuture;
  @override
  void initState(){
    super.initState();
    _reloadMaps();
  }

  void _reloadMaps(){
    _mapsFuture = getMaps();
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: Text("Map Editor",
        style: Theme.of(context).textTheme.titleLarge),
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      body: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.add,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text("Add New Map",
            style: Theme.of(context).textTheme.bodyMedium),
            onTap: () async {
              final shouldReload = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GoogleMaps()),
              );
              if(shouldReload == true){
                setState((){
                  _reloadMaps();
                });
              }
            },
          ),
          Expanded(
            child: FutureBuilder<List<MapFile>>(
              future: _mapsFuture,
              builder: (context, snapshot){
                if(snapshot.connectionState == ConnectionState.waiting){
                  return const Center(child: CircularProgressIndicator());
                }
                if(snapshot.hasError){
                  return const Center(child: Text("Error loading maps"));
                }
                final maps = snapshot.data ?? [];
                if(maps.isEmpty){
                  return const Center(child: Text("No maps found"));
                }
                return ListView.builder(
                  itemCount: maps.length,
                  itemBuilder: (context, index){
                    final map = maps[index];
                    return ListTile(
                      leading: Icon(Icons.map),
                      title: Text(map.mapName),
                      onTap: () async {
                        if(!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>ExampleGame(
                              map: map,
                            ),
                          ),
                        );
                        //   MaterialPageRoute(
                        //     builder: (_) => MapViewer(
                        //       map: map,
                        //     ),
                        //   ),
                        // );
                      },
                      trailing: IconButton(
                        icon: Icon(
                          Icons.delete,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text("Delete Map"),
                              content: const Text("Are you sure you want to delete this map?\nAny replaying for this map will also be deleted."),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
                              ],
                            ),
                          );

                          if(confirm == true){
                            await map.delete();
                            if(!context.mounted) return;
                            setState((){
                              _reloadMaps();
                            });
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}