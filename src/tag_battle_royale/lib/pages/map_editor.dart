import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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

  Future<ui.Image> _getImage(Uint8List bytes) async{
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: const Text("Map Editor"),
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text("Add New Map"),
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
                      leading: const Icon(Icons.map),
                      title: Text(map.mapName),
                      onTap: () async {
                        final image = await _getImage(base64Decode(map.imageBase64));
                        if(!context.mounted) return;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapViewer(
                              image: image,
                              graph: map.graph,
                              mapName: map.mapName,
                            ),
                          ),
                        );
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text("Delete Map"),
                              content: const Text("Are you sure you want to delete this map?"),
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