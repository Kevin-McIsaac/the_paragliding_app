import 'package:free_flight_log/services/paragliding_earth_api.dart';

void main() async {
  final api = ParaglidingEarthApi.instance;

  print('Fetching PGE site details for coordinates: 47.0986, 11.3243');

  try {
    final details = await api.getSiteDetails(47.0986, 11.3243);

    if (details != null) {
      print('\n=== PGE Site Details ===');
      details.forEach((key, value) {
        print('$key: $value');
      });
    } else {
      print('No site details found for these coordinates');
    }
  } catch (e) {
    print('Error fetching site details: $e');
  }
}