import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://photon.komoot.io/api/?q=Panvel&limit=5');
  try {
    final response = await http.get(url, headers: {'Accept': 'application/json', 'User-Agent': 'GeoRide/1.0'});
    print('Status: ${response.statusCode}');
    print('Body Length: ${response.body.length}');
  } catch(e) {
    print('Error: $e');
  }
}
