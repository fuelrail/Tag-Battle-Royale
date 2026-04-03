import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../util/replay/replay_file_handler.dart';
import '../util/replay/replay.dart';
import '../util/mapPainter/map_painter.dart';
import '../util/mapPainter/user_painter.dart';
import '../widgets/map_transform.dart';
import '../widgets/TabButton.dart';

class ReplayViewer extends StatefulWidget {
  const ReplayViewer({
    super.key,
    required this.replayFile,
    required this.image,
  });

  final ReplayFile replayFile;
  final ui.Image image;

  @override
  State<ReplayViewer> createState() => _ReplayViewerState();
}

class _ReplayViewerState extends State<ReplayViewer> {
	Timer? _timer;

	bool showLabel = true;
	bool _isPlaying = false;
	bool _bottomBarCollapsed = false;
	BottomTab _activeTab = BottomTab.replay;

	double _currentTime = 0.0;
	final double _updatesPerSecond = 30.0;
	final double _playbackSpeed = 1.0;

	late Set<String> _selectedPlayerIds;

	double get _maxTime {
		double maxTime = 0.0;
		for(final replay in widget.replayFile.replays){
			if(replay.positions.isNotEmpty){
				final replayEnd = replay.positions.last.time;
				if(replayEnd > maxTime){
				maxTime = replayEnd;
				}
			}
		}
		return maxTime;
	}

  @override
  void initState(){
    super.initState();
    _selectedPlayerIds = widget.replayFile.replays.map((r) => r.playerID).toSet();
  }

  @override
  void dispose(){
    _timer?.cancel();
    super.dispose();
  }

  void _play(){
    if(_isPlaying) return;
    if(_maxTime <= 0) return;
    _timer?.cancel();
    setState(()=> _isPlaying = true);
    _timer = Timer.periodic(Duration(milliseconds: (1000 / _updatesPerSecond).round()),(_){
			if(!mounted) return;
			final nextTime = _currentTime + ((1 / _updatesPerSecond) * _playbackSpeed);
			if(nextTime >= _maxTime){
				_timer?.cancel();
				_timer = null;
				setState((){
					_currentTime = _maxTime;
					_isPlaying = false;
				});
				return;
			}
			setState(()=> _currentTime = nextTime);
    });
  }

  void _pause(){
    _timer?.cancel();
    _timer = null;
    if(!mounted) return;
    setState(()=> _isPlaying = false);
  }

  void _reset(){
    _timer?.cancel();
    _timer = null;
    setState((){
      _isPlaying = false;
      _currentTime = 0.0;
    });
  }

  void _togglePlayPause(){
    if(_isPlaying){
      _pause();
    } else {
      _play();
    }
  }

  void _togglePlayerSelection(String playerID){
    setState((){
      if(_selectedPlayerIds.contains(playerID)){
        _selectedPlayerIds.remove(playerID);
      } else {
        _selectedPlayerIds.add(playerID);
      }
    });
  }

  void _collapseBottomBar(){
    setState(()=> _bottomBarCollapsed = true);
  }

  void _openTab(BottomTab tab){
    setState((){
      _bottomBarCollapsed = false;
      _activeTab = tab;
    });
  }
	// used to smooth between two positions
  ui.Offset? _getPositionAtTime(Replay replay, double time){
    if(replay.positions.isEmpty) return null;
    if(time <= replay.positions.first.time){
      return replay.positions.first.position;
    }
    if(time >= replay.positions.last.time){
      return replay.positions.last.position;
    }
    for(int i = 0; i < replay.positions.length - 1; i++){
      final a = replay.positions[i];
      final b = replay.positions[i + 1];
      if(time >= a.time && time <= b.time){
        final span = b.time - a.time;
        if(span <= 0) return a.position;
        final t = (time - a.time) / span;
        return ui.Offset(
          a.position.dx + ((b.position.dx - a.position.dx) * t),
          a.position.dy + ((b.position.dy - a.position.dy) * t),
        );
      }
    }
    return replay.positions.last.position;
  }

  @override
	Widget build(BuildContext context){
		final imageSize = Size(
			widget.image.width.toDouble(),
			widget.image.height.toDouble(),
		);

		final selectedReplays = widget.replayFile.replays.where(
			(replay) => _selectedPlayerIds.contains(replay.playerID),
		);

		return Scaffold(
			extendBodyBehindAppBar: true,
			appBar: AppBar(
				title: Text(widget.replayFile.replayName),
				titleTextStyle: const TextStyle(
					color: Colors.white,
					fontSize: 20,
					fontWeight: FontWeight.w600,
				),
				iconTheme: const IconThemeData(
					color: Colors.white,
				),
				backgroundColor: const Color.fromARGB(80, 0, 0, 0),
				elevation: 0,
			),
			body: Stack(
				children: [
					// map image
					MapTransform(
						image: widget.image,
						child: Stack(
							children: [
								CustomPaint(
									size: imageSize,
									painter: MapPainter(
										image: widget.image,
										map: widget.replayFile.map,
										drawMode: false,
										drawLabel: true,
									),
								),
								// draw players
								...selectedReplays.map((replay){
									final position = _getPositionAtTime(replay, _currentTime);
									if(position == null) return const SizedBox.shrink();
									return CustomPaint(
										size: imageSize,
										painter: UserPainter(
											position: position,
											colour: replay.colour,
											label: replay.playerName,
											showLabel: showLabel,
										),
									);
								}),
							],
						),
					),
					Positioned(
						left: 0,
						right: 0,
						bottom: 0,
						child: _bottomBarCollapsed ?
						// tabs when collapsed
							SafeArea(
								top: false,
								child: Padding(
									padding: const EdgeInsets.only(left: 0, right: 0, bottom: 0),
									child: Row(
										mainAxisSize: MainAxisSize.min,
										children: [
											TabButton(
												icon: Icons.add,
												selected: false,
												onTap: () => _openTab(_activeTab),
											),
											TabButton(
												icon: Icons.play_arrow,
												selected: false,
												onTap: () => _openTab(BottomTab.replay),
											),
											TabButton(
												icon: Icons.people,
												selected: false,
												onTap: () => _openTab(BottomTab.players),
											),
											TabButton(
												icon: Icons.settings,
												selected: false,
												onTap: () => _openTab(BottomTab.settings),
											),
										],
									),
								),
							) :
							// when tab up
							Stack(
								clipBehavior: Clip.none,
								children: [
									Container(
										margin: const EdgeInsets.only(top: 20),
										padding: EdgeInsets.fromLTRB(
											12,
											18,
											12,
											MediaQuery.of(context).padding.bottom + 10,
										),
										decoration: const BoxDecoration(
											color: Colors.white,
											borderRadius: BorderRadius.vertical(
												top: Radius.circular(20),
											),
										),
										child: Column(
											mainAxisSize: MainAxisSize.min,
											children: [
												// replay tab
												if(_activeTab == BottomTab.replay)
													Row(
														children: [
															IconButton(
																onPressed: _reset,
																icon: const Icon(Icons.replay, color: Colors.black),
															),
															IconButton(
																onPressed: _togglePlayPause,
																icon: Icon(
																	_isPlaying ? Icons.pause : Icons.play_arrow,
																	color: Colors.black,
																),
															),
															Expanded(
																child: SliderTheme(
																	data: SliderTheme.of(context).copyWith(
																		trackHeight: 4,
																		thumbShape: const RoundSliderThumbShape(
																			enabledThumbRadius: 7,
																		),
																		overlayShape: const RoundSliderOverlayShape(
																			overlayRadius: 14,
																		),
																	),
																	child: Slider(
																		value: _currentTime.clamp(
																			0.0,
																			_maxTime == 0 ? 1.0 : _maxTime,
																		),
																		min: 0.0,
																		max: _maxTime == 0 ? 1.0 : _maxTime,
																		onChanged: (value){
																			setState(()=> _currentTime = value);
																		},
																	),
																),
															),
														],
													),
												// players tab
												if(_activeTab == BottomTab.players)
													Column(
														mainAxisSize: MainAxisSize.min,
														children: widget.replayFile.replays.map((replay){
															final selected = _selectedPlayerIds.contains(replay.playerID);
															return Padding(
																padding: const EdgeInsets.symmetric(vertical: 4),
																child: Container(
																	padding: const EdgeInsets.symmetric(
																		horizontal: 10,
																		vertical: 8,
																	),
																	decoration: BoxDecoration(
																		color: const Color.fromARGB(20, 0, 0, 0),
																		borderRadius: BorderRadius.circular(12),
																	),
																	child: InkWell(
																		borderRadius: BorderRadius.circular(12),
																		onTap: (){
																			_togglePlayerSelection(replay.playerID);
																		},
																		child: Row(
																			children: [
																				Container(
																					width: 14,
																					height: 14,
																					decoration: BoxDecoration(
																						color: replay.colour,
																						shape: BoxShape.circle,
																					),
																				),
																				const SizedBox(width: 10),
																				Expanded(
																					child: Text(
																						replay.playerName,
																						style: const TextStyle(
																							color: Colors.black,
																							fontSize: 14,
																						),
																					),
																				),
																				Checkbox(
																					value: selected,
																					onChanged: (_){
																						_togglePlayerSelection(replay.playerID);
																					},
																				),
																			],
																		),
																	),
																),
															);
														}).toList(),
													),
												// settings tab
												if(_activeTab == BottomTab.settings)
													Column(
														mainAxisSize: MainAxisSize.min,
														children: [
															Container(
																padding: const EdgeInsets.symmetric(
																	horizontal: 10,
																	vertical: 8,
																),
																decoration: BoxDecoration(
																	color: const Color.fromARGB(20, 0, 0, 0),
																	borderRadius: BorderRadius.circular(12),
																),
																child: Row(
																	children: [
																		const Expanded(
																			child: Text(
																				'Show labels',
																				style: TextStyle(
																					color: Colors.black,
																					fontSize: 14,
																				),
																			),
																		),
																		Checkbox(
																			value: showLabel,
																			onChanged: (value){
																				setState(()=> showLabel = value ?? true);
																			},
																		),
																	],
																),
															),
														],
													),
											],
										),
									),
									// tabs on the open mode
									Positioned(
										top: 0,
										left: 0,
										child: Row(
											children: [
												TabButton(
													icon: Icons.remove,
													selected: false,
													onTap: _collapseBottomBar,
												),
												TabButton(
													icon: Icons.play_arrow,
													selected: _activeTab == BottomTab.replay,
													onTap: () => _openTab(BottomTab.replay),
												),
												TabButton(
													icon: Icons.people,
													selected: _activeTab == BottomTab.players,
													onTap: () => _openTab(BottomTab.players),
												),
												TabButton(
													icon: Icons.settings,
													selected: _activeTab == BottomTab.settings,
													onTap: () => _openTab(BottomTab.settings),
												),
											],
										),
									),
								],
							),
					),
				],
			),
		);
	}
}

enum BottomTab {
  replay,
  players,
  settings
}