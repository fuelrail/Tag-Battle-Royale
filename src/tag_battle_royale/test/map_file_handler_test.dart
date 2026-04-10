import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:tag_battle_royale/util/map_file_handler.dart';
import 'package:tag_battle_royale/util/faceDetection/face_detection_graph.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('map_file_test_');
    PathProviderPlatform.instance = TempPathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if(await tempDir.exists()){
      await tempDir.delete(recursive: true);
    }
  });

  test('MapFile toJson and fromJson', (){
    final mapFile = MapFile(
      id: '1',
      fileName: '1.json',
      mapName: 'Test Map',
      imageHeight: 1,
      imageWidth: 1,
      imageBase64: 'abc123',
      imageBounds: LatLngBounds(
        southwest: const LatLng(1, 2),
        northeast: const LatLng(3, 4),
      ),
      graph: PlanarGraph.fromJson({
        'vertices': [],
        'edges': [],
        'faces': [],
      }),
    );

    final rebuilt = MapFile.fromJson(mapFile.toJson());

    expect(rebuilt.id, '1');
    expect(rebuilt.fileName, '1.json');
    expect(rebuilt.mapName, 'Test Map');
    expect(rebuilt.imageBase64, 'abc123');
    expect(rebuilt.imageHeight, 1);
    expect(rebuilt.imageWidth, 1);
  });

  test('saveMapFile and getMaps', () async {
    final mapFile = MapFile(
      id: '1',
      fileName: '1.json',
      mapName: 'Test Map',
      imageBase64: 'abc123',
      imageHeight: 1,
      imageWidth: 1,
      imageBounds: LatLngBounds(
        southwest: const LatLng(1, 2),
        northeast: const LatLng(3, 4),
      ),
      graph: PlanarGraph.fromJson({
        'vertices': [],
        'edges': [],
        'faces': [],
      }),
    );

    await mapFile.saveMapFile();
    final maps = await getMaps();

    expect(maps.length, 1);
    expect(maps.first.mapName, 'Test Map');
  });

  test('delete removes file', () async {
    final mapFile = MapFile(
      id: '1',
      fileName: '1.json',
      mapName: 'Test Map',
      imageBase64: 'abc123',
      imageHeight: 1,
      imageWidth: 1,
      imageBounds: LatLngBounds(
        southwest: const LatLng(1, 2),
        northeast: const LatLng(3, 4),
      ),
      graph: PlanarGraph.fromJson({
        'vertices': [],
        'edges': [],
        'faces': [],
      }),
    );

    final file = await mapFile.saveMapFile();
    expect(await file.exists(), isTrue);

    await mapFile.delete();
    expect(await file.exists(), isFalse);
  });
}

class TempPathProviderPlatform extends PathProviderPlatform {
  TempPathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}