import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chilito',
      theme: ThemeData(
        primarySwatch: Colors.purple,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _locationController = TextEditingController();
  String _searchResult = '';

  Future<void> _getGpsLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _locationController.text = '${position.latitude}, ${position.longitude}';
    } catch (e) {
      setState(() {
        _searchResult = 'Could not get location: $e';
      });
    }
  }

  Future<bool> _checkUrlForChilito(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = html.parse(response.body);
        final content = document.body?.text.toLowerCase() ?? '';

        final keywords = [
          'chili cheese burrito',
          'chilito'
        ];

        for (final keyword in keywords) {
          if (content.contains(keyword)) {
            return true;
          }
        }

        // Also check product names specifically
        final productNames = document.querySelectorAll('.product-name');
        for (final nameElement in productNames) {
          final productName = nameElement.text.toLowerCase();
          for (final keyword in keywords) {
            if (productName.contains(keyword)) {
              return true;
            }
          }
        }
      }
    } catch (e) {
      // Ignore errors for individual URL checks
    }
    return false;
  }

  Future<void> _search() async {
    setState(() {
      _searchResult = 'Searching...';
    });

    try {
      // Step 1: Geocode the address to get coordinates
      final encodedLocation = Uri.encodeComponent(_locationController.text);
      final geocodeResponse = await http.get(
        Uri.parse('https://api.tacobell.com/location/v1/$encodedLocation'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36',
          'Accept': 'application/json',
          'Referer': 'https://www.tacobell.com/',
        },
      );

      if (geocodeResponse.statusCode != 200) {
        setState(() {
          _searchResult =
              'Error geocoding location (Status: ${geocodeResponse.statusCode}).';
        });
        return;
      }

      final geocodeData = json.decode(geocodeResponse.body);
      if (geocodeData['success'] != true || geocodeData['geometry'] == null) {
        setState(() {
          _searchResult = 'Could not find coordinates for the location.';
        });
        return;
      }

      final lat = geocodeData['geometry']['lat'];
      final lng = geocodeData['geometry']['lng'];

      // Step 2: Find stores near the coordinates
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storesResponse = await http.get(
        Uri.parse(
            'https://www.tacobell.com/tacobellwebservices/v4/tacobell/stores?latitude=$lat&longitude=$lng&_=$timestamp'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Referer': 'https://www.tacobell.com/locations',
        },
      );

      if (storesResponse.statusCode != 200) {
        setState(() {
          _searchResult =
              'Error finding stores (Status: ${storesResponse.statusCode}).';
        });
        return;
      }

      // The new endpoint returns a simple list of stores directly.
      final storesData = json.decode(storesResponse.body);
      final stores = storesData['nearByStores'] as List? ?? [];

      if (stores.isEmpty) {
        setState(() {
          _searchResult = 'No Taco Bell locations found nearby.';
        });
        return;
      }

      // Step 3: Check the menu for the closest 5 stores
      for (var i = 0; i < stores.length && i < 5; i++) {
        final store = stores[i];
        if (store == null) continue;

        final storeDetails = store['store'];
        if (storeDetails == null) continue;

        final storeId = storeDetails['storeNumber'];
        final storeName = storeDetails['storeName'] ?? 'a nearby Taco Bell';
        final address = storeDetails['contacts']?['address'];
        final String fullAddress;
        if (address != null) {
          fullAddress = '${address['street']}, ${address['city']}, ${address['state']} ${address['postalCode']}';
        } else {
          fullAddress = 'Address not available';
        }


        final urlsToCheck = [
          'https://www.tacobell.com/food/menu?store=$storeId',
          'https://www.tacobell.com/food/burritos?store=$storeId',
          'https://www.tacobell.com/food/specialty?store=$storeId',
        ];

        for (final url in urlsToCheck) {
          if (await _checkUrlForChilito(url)) {
            setState(() {
              _searchResult =
                  'Taco Bell at $storeName ($fullAddress) has the Chili Cheese Burrito!';
            });
            return; // Found it, so we can stop
          }
        }
      }

      // 4. If the loop completes, it wasn't found
      setState(() {
        _searchResult = 'No Taco Bells nearby sell the chili cheese burrito.';
      });
    } catch (e) {
      setState(() {
        _searchResult =
            'Failed to search. Please check your connection and try again. Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF702082), // Taco Bell Purple
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
              'assets/chili-cheese-burrito.png'), // Placeholder icon
        ),
        title: const Text('Chilito', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Enter your location',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8.0),
            ElevatedButton.icon(
              onPressed: _getGpsLocation,
              icon: const Icon(Icons.gps_fixed),
              label: const Text('Use GPS Location'),
            ),
            const SizedBox(height: 8.0),
            ElevatedButton(
              onPressed: _search,
              child: const Text('Search'),
            ),
            const SizedBox(height: 16.0),
            Text(
              _searchResult,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
