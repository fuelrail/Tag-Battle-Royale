import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';
import "faceDetection/face_detection_graph.dart";

// For saving and laoding Map Files

// check all json files in app documents directory
// deletes any json files that are broken -> debug mode
Future<List<MapFile>> getMaps() async {
  final dir = await getMapsDirectory();
  final files = dir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList();

  final maps = <MapFile>[];
  for(final file in files){
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if(decoded is! Map<String, dynamic>){
        throw Exception('Invalid root JSON');
      }

      maps.add(MapFile.fromJson(decoded));

    } catch (e){
      if(kDebugMode){
        debugPrint('Deleting broken file: ${file.path} -> $e');
        try {
          await file.delete();
        } catch (_){}
      }
    }
  }
  return maps;
}

Future<MapFile?> getMapByID(String id) async {
  final maps = await getMaps();
  for(final map in maps){
    if(map.id == id){
      return map;
    }
  }
  return null;
}

Future<Directory> getMapsDirectory() async {
  final rootDir = await getApplicationDocumentsDirectory();
  final mapsDir = Directory('${rootDir.path}/maps');

  if(!await mapsDir.exists()){
    await mapsDir.create(recursive: true);
  }

  return mapsDir;
}

class MapFile {
  final String id;
  final String fileName;
  final String mapName;
  final String imageBase64;
  final LatLngBounds imageBounds;
  final int imageHeight;
  final int imageWidth;
  final PlanarGraph graph;

  MapFile({
    required this.id,
    required this.fileName,
    required this.mapName,
    required this.imageBase64,
    required this.imageBounds,
    required this.imageHeight,
    required this.imageWidth,
    required this.graph,
  });
  Future<ui.Image> getImage() async {
    final codec = await ui.instantiateImageCodec(base64Decode(imageBase64));
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  // converts Map file to json
  Map<String, dynamic> toJson(){
    return {
      'id': id,
      'fileName': fileName,
      'mapName': mapName,
      'imageBounds': {
        'southwest': {
          'latitude': imageBounds.southwest.latitude,
          'longitude': imageBounds.southwest.longitude,
        },
        'northeast': {
          'latitude': imageBounds.northeast.latitude,
          'longitude': imageBounds.northeast.longitude,
        },
      },
      'imageBase64': imageBase64,
      'imageHeight': imageHeight,
      'imageWidth': imageWidth,
      'graph': graph.toJson(),
    };
  }
  // to build the json file returns string
  String makeFile(){
    return jsonEncode(toJson());
  }
  // converts a json fiel into a MapFile
  factory MapFile.fromJson(Map<String, dynamic> json){
    final boundsJson = json['imageBounds'] as Map<String, dynamic>;

    final southwest = boundsJson['southwest'] as Map<String, dynamic>;
    final northeast = boundsJson['northeast'] as Map<String, dynamic>;

    return MapFile(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      mapName: json['mapName'] as String,
      imageBounds: LatLngBounds(
        southwest: LatLng(
          (southwest['latitude'] as num).toDouble(),
          (southwest['longitude'] as num).toDouble(),
        ),
        northeast: LatLng(
          (northeast['latitude'] as num).toDouble(),
          (northeast['longitude'] as num).toDouble(),
        ),
      ),
      imageBase64: json['imageBase64'] as String,
      imageHeight: json['imageHeight'] as int,
      imageWidth: json['imageWidth'] as int,
      graph: PlanarGraph.fromJson(json['graph'] as Map<String, dynamic>),
    );
  }
  // a unique id used to store the Map files
  static String _generateUniqueId(){
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(1 << 32);
    return '${now}_$random';
  }
  // creates map file and generates a unique id for map file
  static Future<MapFile> create({
    required ui.Image image,
    required LatLngBounds imageBounds,
    required String name,
    required PlanarGraph graph,
  }) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if(byteData == null){
      throw Exception('Failed to convert image to bytes');
    }

    final Uint8List bytes = byteData.buffer.asUint8List();
    final String imageBase64 = base64Encode(bytes);
    final id = _generateUniqueId();
    final fileName = '$id.json';
    final imageHeight = image.height;
    final imageWidth = image.width;

    return MapFile(
      mapName: name,
      id: id,
      fileName: fileName,
      imageBase64: imageBase64,
      imageBounds: imageBounds,
      imageHeight: imageHeight,
      imageWidth: imageWidth,
      graph: graph,
    );
  }

  Future<File> saveMapFile() async {
    final dir = await getMapsDirectory();
    final file = File('${dir.path}/$fileName');
    return file.writeAsString(makeFile());
  }

  Future<void> delete() async {
    final dir = await getMapsDirectory();
    final file = File('${dir.path}/$fileName');

    if(await file.exists()){
      await file.delete();
    }
  }
}