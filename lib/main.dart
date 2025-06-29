import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:url_launcher/url_launcher.dart';

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
  Widget _searchResult = const SizedBox.shrink();
  double? _foundLat;
  double? _foundLng;

  Future<void> _getGpsLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _locationController.text = '${position.latitude}, ${position.longitude}';
    } catch (e) {
      setState(() {
        _searchResult = Text('Could not get location: $e');
      });
    }
  }

  Future<bool> _checkUrlForChilito(String url) async {
    try {
      print('Checking URL: $url');
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Referer': 'https://www.tacobell.com/locations',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
      });

      if (response.statusCode == 200) {
        final document = html.parse(response.body);
        final content = document.body?.text.toLowerCase() ?? '';

        final keywords = [
          'chili cheese burrito',
          'chilito',
          'chili burrito',
        ];

        for (final keyword in keywords) {
          if (content.contains(keyword)) {
            print('Found keyword: "$keyword" in page content at $url');
            return true;
          }
        }
        print('Keyword not found at $url.');
      } else {
        print('Failed to fetch $url - Status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error checking URL $url: $e');
    }
    return false;
  }

  Future<void> _testPrint() async {
    print("--- BUTTON TEST: The Search button was definitely pressed. ---");
  }

  Future<void> _search() async {
    print('--- SEARCH BUTTON PRESSED ---');
    setState(() {
      _searchResult = const Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 10),
          Text('Searching...'),
        ],
      );
      _foundLat = null;
      _foundLng = null;
    });

    // Add a check for empty location
    if (_locationController.text.trim().isEmpty) {
      print('Search failed: Location is empty.');
      setState(() {
        _searchResult = const Text('Please enter a location first.');
      });
      return;
    }

    try {
      // Step 1: Geocode the address to get coordinates
      print('Step 1: Geocoding location: "${_locationController.text}"');
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
      print('Geocode response status: ${geocodeResponse.statusCode}');

      if (geocodeResponse.statusCode != 200) {
        setState(() {
          _searchResult =
              Text('Error geocoding location (Status: ${geocodeResponse.statusCode}).');
        });
        return;
      }

      final geocodeData = json.decode(geocodeResponse.body);
      print('Geocode response data: $geocodeData');
      if (geocodeData['success'] != true || geocodeData['geometry'] == null) {
        setState(() {
          _searchResult = const Text('Could not find coordinates for the location.');
        });
        return;
      }

      final lat = geocodeData['geometry']['lat'];
      final lng = geocodeData['geometry']['lng'];
      print('Coordinates found: lat=$lat, lng=$lng');

      // Step 2: Find stores near the coordinates
      print('Step 2: Finding stores...');
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
      print('Stores response status: ${storesResponse.statusCode}');

      if (storesResponse.statusCode != 200) {
        setState(() {
          _searchResult =
              Text('Error finding stores (Status: ${storesResponse.statusCode}).');
        });
        return;
      }

      final storesData = json.decode(storesResponse.body);
      final stores = storesData['nearByStores'] as List? ?? [];
      print('Found ${stores.length} stores nearby.');

      if (stores.isEmpty) {
        setState(() {
          _searchResult = const Text('No Taco Bell locations found nearby.');
        });
        return;
      }

      // Step 3: Check the menu for the closest 5 stores
      print('Step 3: Checking menus...');
      for (var i = 0; i < stores.length && i < 5; i++) {
        final store = stores[i];
        if (store == null) continue;

        // FINAL CORRECTED PARSING LOGIC:
        final storeId = store['storeNumber'];
        final storeName = 'Taco Bell #${store['storeNumber']}'; // Construct a better name
        final address = store['address'];
        final String fullAddress;
        if (address != null && address is Map) {
          final street = address['line1'] ?? '';
          final city = address['town'] ?? '';
          final regionData = address['region'];
          String state = '';
          if (regionData != null &&
              regionData is Map &&
              regionData['isocode'] != null) {
            state = (regionData['isocode'] as String).split('-').last;
          }
          final postalCode = address['postalCode'] ?? '';
          fullAddress = '$street, $city, $state $postalCode';
        } else {
          fullAddress = 'Address not available';
        }

        if (storeId == null) {
          print('Skipping a store because it has no storeNumber.');
          continue;
        }

        final urlsToCheck = [
          'https://www.tacobell.com/food/menu?store=$storeId',
          'https://www.tacobell.com/food/burritos?store=$storeId',
          'https://www.tacobell.com/food/specialty?store=$storeId',
        ];

        for (int j = 0; j < urlsToCheck.length; j++) {
          final url = urlsToCheck[j];
          if (await _checkUrlForChilito(url)) {
            print('--- SEARCH FINISHED: Found! ---');
            setState(() {
              // Save the coordinates of the found store
              _foundLat = store['geoPoint']?['latitude'];
              _foundLng = store['geoPoint']?['longitude'];

              _searchResult = Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'YES! Found at the closest Taco Bell:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        storeName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fullAddress,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      if (_foundLat != null && _foundLng != null)
                        ElevatedButton.icon(
                          onPressed: _launchNavigation,
                          icon: const Icon(Icons.navigation),
                          label: const Text('Navigate'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            });
            return; // Found it, so we can stop
          }
          // Add a small delay between requests
          await Future.delayed(const Duration(milliseconds: 250));
        }
      }

      // 4. If the loop completes, it wasn't found
      print('--- SEARCH FINISHED: Not found ---');
      setState(() {
        _searchResult = const Text('No Taco Bells nearby sell the chili cheese burrito.');
        _foundLat = null;
        _foundLng = null;
      });
    } catch (e) {
      print('--- SEARCH FAILED WITH ERROR ---');
      print(e.toString()); // This will print the actual error
      setState(() {
        _searchResult =
            Text('Failed to search. Please check your connection and try again. Error: $e');
        _foundLat = null;
        _foundLng = null;
      });
    }
  }

  Future<void> _launchNavigation() async {
    if (_foundLat != null && _foundLng != null) {
      final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$_foundLat,$_foundLng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        setState(() {
          _searchResult = const Text('Could not open navigation app.');
        });
      }
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
              onPressed: _search, // Changed back to the real search function
              child: const Text('Search'),
            ),
            const SizedBox(height: 16.0),
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: _searchResult,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
