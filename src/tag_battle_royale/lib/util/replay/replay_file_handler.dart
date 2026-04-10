import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../map_file_handler.dart';
import '../replay/replay.dart';

class ReplayFile {
  final String id;
  final String fileName;
  final String replayName;
  final MapFile map;
  final List<Replay> replays;

  /// faceID -> closing time in seconds
  final Map<int, double> zoneClosings;

  ReplayFile({
    required this.id,
    required this.fileName,
    required this.replayName,
    required this.map,
    List<Replay>? replays,
    Map<int, double>? zoneClosings,
  })  : replays = replays ?? [],
        zoneClosings = zoneClosings ?? {};

  void addReplay(Replay replay){
    replays.removeWhere((r) => r.playerID == replay.playerID);
    replays.add(replay);
  }

  void addZoneClosing({
    required int faceID,
    required double time,
  }){
    final existing = zoneClosings[faceID];

    if(existing == null || time < existing){
      zoneClosings[faceID] = time;
    }
  }

  bool isZoneClosedAtTime({
    required int faceID,
    required double time,
  }){
    final closingTime = zoneClosings[faceID];
    if(closingTime == null) return false;
    return time >= closingTime;
  }

  List<int> getClosedZoneIdsAtTime(double time){
    return zoneClosings.entries
        .where((entry) => time >= entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  Map<String, dynamic> toJson(){
    return {
      'id': id,
      'fileName': fileName,
      'replayName': replayName,
      'map': map.toJson(),
      'replays': replays.map((r) => r.toJson()).toList(),
      'zoneClosings': zoneClosings.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    };
  }

  String makeFile(){
    return jsonEncode(toJson());
  }

  factory ReplayFile.fromJson(Map<String, dynamic> json){
    final zoneClosingsJson =
        (json['zoneClosings'] as Map?)?.cast<String, dynamic>() ?? {};

    return ReplayFile(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      replayName: json['replayName'] as String,
      map: MapFile.fromJson(json['map'] as Map<String, dynamic>),
      replays: (json['replays'] as List)
          .map((r) => Replay.fromJson(Map<String, dynamic>.from(r)))
          .toList(),
      zoneClosings: zoneClosingsJson.map(
        (key, value) => MapEntry(
          int.parse(key),
          (value as num).toDouble(),
        ),
      ),
    );
  }

  static String _generateUniqueId(){
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(1 << 32);
    return '${now}_$random';
  }

  static Future<ReplayFile> create({
    required MapFile map,
    List<Replay>? replays,
    Map<int, double>? zoneClosings,
  }) async {
    final id = _generateUniqueId();
    final fileName = '$id.json';
    final now = DateTime.now();
    final replayName =
        'Replay of ${map.mapName} on ${now.day}/${now.month}/${now.year}';

    return ReplayFile(
      id: id,
      fileName: fileName,
      replayName: replayName,
      map: map,
      replays: replays,
      zoneClosings: zoneClosings,
    );
  }

  Future<File> saveReplayFile() async {
    final dir = await getReplaysDirectory();
    final file = File('${dir.path}/$fileName');
    return file.writeAsString(makeFile());
  }

  Future<void> delete() async {
    final dir = await getReplaysDirectory();
    final file = File('${dir.path}/$fileName');

    if(await file.exists()){
      await file.delete();
    }
  }
}

Future<Directory> getReplaysDirectory() async {
  final rootDir = await getApplicationDocumentsDirectory();
  final replaysDir = Directory('${rootDir.path}/replays');

  if(!await replaysDir.exists()){
    await replaysDir.create(recursive: true);
  }

  return replaysDir;
}

Future<List<ReplayFile>> getReplayFiles() async {
  final dir = await getReplaysDirectory();
  final files = dir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList();

  final replayFiles = <ReplayFile>[];

  for(final file in files){
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);

      if(decoded is! Map<String, dynamic>){
        throw Exception('Invalid root JSON');
      }

      replayFiles.add(ReplayFile.fromJson(decoded));
    } catch (e){
      debugPrint('Skipping broken replay file: ${file.path} -> $e');
    }
  }

  return replayFiles;
}