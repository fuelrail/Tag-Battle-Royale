import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_styled_toast/flutter_styled_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_nearby_connections_plus/flutter_nearby_connections_plus.dart';

void main() {
  runApp(MyApp());
}

Route<dynamic> generateRoute(RouteSettings settings) {
  switch (settings.name) {
    case '/':
      return MaterialPageRoute(builder: (_) => Home());
    case 'join':
      return MaterialPageRoute(builder: (_) => JoinListScreen());
    case 'host':
      return MaterialPageRoute(builder: (_) => HostListScreen());
    default:
      return MaterialPageRoute(
          builder: (_) => Scaffold(
                body: Center(
                    child: Text('No route defined for ${settings.name}')),
              ));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateRoute: generateRoute,
      initialRoute: '/',
    );
  }
}

class Home extends StatelessWidget {
  const Home({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                Navigator.pushNamed(context, 'join');
              },
              child: Container(
                color: Colors.red,
                child: Center(
                    child: Text(
                  'JOIN',
                  style: TextStyle(color: Colors.white, fontSize: 40),
                )),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () {
                Navigator.pushNamed(context, 'host');
              },
              child: Container(
                color: Colors.green,
                child: Center(
                    child: Text(
                  'HOST',
                  style: TextStyle(color: Colors.white, fontSize: 40),
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum DeviceType { host, pseudohost, player }

//class ExtendedDevice extends Device {
//  //bool isBrowser;
//  
//  ExtendedDevice(
//    super.deviceId,
//    super.deviceName,
//    super.state,
//    //this.isBrowser,
//  );
//  
//  // Factory constructor to create ExtendedDevice from JSON
//  factory ExtendedDevice.fromJson(Map<String, dynamic> json) {
//    return ExtendedDevice(
//      json["deviceId"],
//      json["deviceName"],
//      json["state"],
//      //isBrowser,
//    );
//  }
//  
//  // Factory constructor to create ExtendedDevice from existing Device
//  factory ExtendedDevice.fromDevice(Device device) {
//    // Convert SessionState back to int for the parent constructor
//    return ExtendedDevice(
//      device.deviceId,
//      device.deviceName,
//      _sessionStateToInt(device.state),
//      //isBrowser,
//    );
//  }
//
//    // Helper method to convert SessionState to int
//  static int _sessionStateToInt(SessionState state) {
//    switch (state) {
//      case SessionState.notConnected:
//        return 0;
//      case SessionState.connecting:
//        return 1;
//      case SessionState.connected:
//        return 2;
//      default:
//        return 0;
//    }
//  }
//  
//  // Helper method to convert ExtendedDevice back to Map for JSON
//  Map<String, dynamic> toJson() {
//    return {
//      "deviceId": deviceId,
//      "deviceName": deviceName,
//      "state": _sessionStateToInt(state),
//      //"isBrowser": isBrowser,
//    };
//  }
//}

class Node {
  Device? data;
  Node? parent;
  final List<Node> children = [];
  int descendantCount = 0;

  Node(this.data);

  void addDevice(Device childData) {
    Node child = Node(childData);
    child.parent = this;
    children.add(child);

    // Child itself + all of its descendants
    _propagateCountUp(1);
  }

  void removeDevice(Device childData) {
    Node targetNode = children.firstWhere((node) => node.data?.deviceId == childData.deviceId);
    
    if (children.remove(targetNode)) {
      targetNode.parent = null;

      // Remove child itself + its descendants
      _propagateCountUp(-(1 + targetNode.descendantCount));
    }
  }

  List<Device> getChildrenDevices() => children.map((child) => child.data).whereType<Device>().toList();

  void _propagateCountUp(int delta) {
    descendantCount += delta;
    parent?._propagateCountUp(delta);
  }

  void preOrderTraversal() {
    if (data == null) return;

    for (var child in children) {
      child.preOrderTraversal();
    }
  }
}

class HostListScreen extends StatefulWidget {
  const HostListScreen({super.key});
  
  @override
  State<HostListScreen> createState() => _HostListScreenState(); // changed this
}

class _HostListScreenState extends State<HostListScreen> {
  List<Device> devices = [];
  List<Device> connectedDevices = [];
  
  late NearbyService nearbyService;
  late StreamSubscription subscription;
  late StreamSubscription receivedDataSubscription;

  static const int MAX_DIRECT_CONNECTIONS = 2;
  late Node deviceTree;
  
  bool isInit = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    subscription.cancel();
    receivedDataSubscription.cancel();
    nearbyService.stopBrowsingForPeers();
    nearbyService.stopAdvertisingPeer();
    super.dispose();
  }

  void init() async {
    nearbyService = NearbyService();
    String devInfo = '';
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo; // could check for ios here
    devInfo = androidInfo.model;

    await nearbyService.init(
        serviceType: 'mpconn',
        deviceName: devInfo,
        strategy: Strategy.P2P_CLUSTER,
        callback: (isRunning) async {
          if (isRunning) {
            await nearbyService.stopAdvertisingPeer();
            await Future.delayed(Duration(microseconds: 200));
            await nearbyService.startAdvertisingPeer();
          }
        });

    nearbyService.stateChangedSubscription(callback: (devicesList) {
      devicesList.forEach((element) {
          print(" deviceId: ${element.deviceId} | deviceName: ${element.deviceName} | state: ${element.state}");
        });

      setState(() {
        devices.clear();
        devices.addAll(devicesList);
        connectedDevices.clear();
        connectedDevices.addAll(devicesList
            .where((d) => d.state == SessionState.connected)
            .toList());
      });

      List<String> newConnectedIds = connectedDevices.map((d) => d.deviceId).toList();

      for (Device oldConnectedDevice in deviceTree.getChildrenDevices()) {
        if (!newConnectedIds.contains(oldConnectedDevice.deviceId)) {
          // device has disconnected
          // might need to do more idk
          deviceTree.removeDevice(oldConnectedDevice);
        }
      }
      
      // !oldConnectedIds.contains(connectedDevice.deviceId) 
      for (Device connectedDevice in connectedDevices) {
        List<Device> oldConnectedDevices = deviceTree.getChildrenDevices();
        if (!oldConnectedDevices.map((d) => d.deviceId).toList().contains(connectedDevice.deviceId)) {
          // This is a new player
          // Check if we need to redirect
          if (deviceTree.children.length > MAX_DIRECT_CONNECTIONS) {
            // We have more players than we can handle directly
            // Find an existing player to redirect to (not the new one)
            Node lowestDescendentCountNode = deviceTree.children[0];
            for (Node child in deviceTree.children.skip(1)) {
              if ((child.descendantCount) < (lowestDescendentCountNode.descendantCount)) {
                lowestDescendentCountNode = child;
              }
            }
            // send them away
            _sendRedirectionMessage(connectedDevice, lowestDescendentCountNode.data!);
          } else {
            deviceTree.addDevice(connectedDevice);
          }
        }
      }
    });

    receivedDataSubscription =
        nearbyService.dataReceivedSubscription(callback: (data) {
      print("dataReceivedSubscription: ${jsonEncode(data)}");
      
      // Handle redirection messages
      if (data['type'] == 'redirect') {
        _handleRedirectionMessage(data);
      } else {
        showToast(jsonEncode(data),
            context: context,
            axis: Axis.horizontal,
            alignment: Alignment.center,
            position: StyledToastPosition.bottom);
      }
    });
  }

  void _handleRedirections(List<Device> oldConnected, List<Device> newConnected) {
    // Find newly connected devices
    final newlyConnected = newConnected.where((newDev) => 
      !oldConnected.any((oldDev) => oldDev.deviceId == newDev.deviceId)
    ).toList();

    for (var newDevice in newlyConnected) {
      // Check if this device needs redirection
      final redirectionInfo = connectionManager.getRedirectionInfo(newDevice.deviceId);
      
      if (redirectionInfo != null) {
        // Find the target host device
        Device? targetHost = newConnected.firstWhere(
          (d) => d.deviceId == redirectionInfo['hostId'],
          orElse: () => Device(redirectionInfo['hostId']!, 'Unknown Host', 0),
        );

        // Only redirect if the target is not this device itself
        if (targetHost.deviceId != newDevice.deviceId) {
          _sendRedirectionMessage(newDevice, targetHost, redirectionInfo['role']!);
        }
      }
    }
  }

  void _sendRedirectionMessage(Device clientDevice, Device hostDevice, String role) {
    final redirectMessage = jsonEncode({
      'type': 'redirect',
      'targetId': hostDevice.deviceId,
      'targetName': hostDevice.deviceName,
      'role': role,
      'message': 'Please connect to ${hostDevice.deviceName}'
    });
    
    nearbyService.sendMessage(clientDevice.deviceId, redirectMessage);
    print("Sent redirection to ${clientDevice.deviceName} → ${hostDevice.deviceName}");
  }

  void _handleRedirectionMessage(Map<String, dynamic> data) {
    print("Received redirection: $data");
  }
}
