import 'package:geolocator/geolocator.dart';

Future<Position> getLocation(){
  return _determinePosition();

}
/// Determine the current position of the device.
/// When the location services are not enabled or permissions
/// are denied will return an error.
Future<Position> _determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;
  // Test if location services are enabled.
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if(!serviceEnabled){
    return Future.error('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if(permission == LocationPermission.denied){
    permission = await Geolocator.requestPermission();
    if(permission == LocationPermission.denied){
      return Future.error('Location permissions are denied');
    }
  }
  
  if(permission == LocationPermission.deniedForever){
    return Future.error(
      'Location permissions are permanently denied, we cannot request permissions.');
  } 
  final LocationSettings locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
  );
  // continue accessing the position of the device.
  return await Geolocator.getCurrentPosition(locationSettings: locationSettings);
}