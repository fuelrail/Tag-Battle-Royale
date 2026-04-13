import 'package:flutter/material.dart';

import '../util/replay/replay_file_handler.dart';
import '../widgets/replay_viewer.dart';

class ReplayPage extends StatefulWidget {
  const ReplayPage({super.key});

  @override
  State<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends State<ReplayPage> {
  late Future<List<ReplayFile>> _replaysFuture;

  @override
  void initState(){
    super.initState();
    _reloadReplays();
  }

  void _reloadReplays(){
    _replaysFuture = getReplayFiles();
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text("Replays", style: Theme.of(context).textTheme.titleLarge,),
      ),
      body: FutureBuilder<List<ReplayFile>>(
        future: _replaysFuture,
        builder: (context, snapshot){
          if(snapshot.connectionState == ConnectionState.waiting){
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if(snapshot.hasError){
            return const Center(
              child: Text("Error loading replays"),
            );
          }

          final replays = snapshot.data ?? [];

          if(replays.isEmpty){
            return const Center(
              child: Text("No replays found"),
            );
          }

          return ListView.builder(
            itemCount: replays.length,
            itemBuilder: (context, index){
              final replayFile = replays[index];

              return ListTile(
                leading: Icon(Icons.play_circle_outline, color: Theme.of(context).colorScheme.primary,),
                title: Text(replayFile.replayName, style: Theme.of(context).textTheme.titleLarge),
                onTap: () async {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReplayViewer(
                        replayFile: replayFile,
                      ),
                    ),
                  );
                },
                trailing: IconButton(
                  icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text("Delete Replay"),
                        content: const Text(
                          "Are you sure you want to delete this replay?",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text("Cancel"),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text("Delete"),
                          ),
                        ],
                      ),
                    );

                    if(confirm == true){
                      await replayFile.delete();

                      if(!context.mounted) return;

                      setState((){
                        _reloadReplays();
                      });
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}