import 'package:flutter/material.dart';
import '../widgets/cesium_token_manager.dart';

/// Enable user to their own token to unlocking premium maps
class CesiumSettingsDemoScreen extends StatefulWidget {
  const CesiumSettingsDemoScreen({super.key});

  @override
  State<CesiumSettingsDemoScreen> createState() => _CesiumSettingsDemoScreenState();
}

class _CesiumSettingsDemoScreenState extends State<CesiumSettingsDemoScreen> {
  void _onTokenChanged() {
    // Handle token changes if needed
    // This could refresh the parent widget, show a notification, etc.
    setState(() {
      // Trigger rebuild to show updated state
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cesium Acess Token'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Free Premium Maps',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'To unlock free access to premium Bing Maps you need to provide your own Cesium ION acess token.\n'
              'Registering with Cesium is free, quick and easy',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            CesiumTokenManager(
              onTokenChanged: _onTokenChanged,
            ),
            const SizedBox(height: 24),
            
          ],
        ),
      ),
    );
  }
}