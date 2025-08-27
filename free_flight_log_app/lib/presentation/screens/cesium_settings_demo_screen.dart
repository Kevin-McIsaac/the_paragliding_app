import 'package:flutter/material.dart';
import '../widgets/cesium_token_manager.dart';

/// Demo screen to showcase the Cesium Ion token management feature
/// This demonstrates the user-provided token feature for unlocking premium maps
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
        title: const Text('Cesium Settings Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Premium Map Token Management',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This demonstrates the user-provided Cesium Ion token feature. '
              'Users can add their own token to unlock premium Bing Maps imagery providers.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            CesiumTokenManager(
              onTokenChanged: _onTokenChanged,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Feature Benefits:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('Higher Resolution Imagery'),
                  subtitle: Text('Up to 19-22 zoom levels with Bing Maps'),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('Multiple Map Options'),
                  subtitle: Text('Aerial, Aerial with Labels, and Road maps'),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('Free Tier Available'),
                  subtitle: Text('5GB monthly quota at no cost'),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('Secure Token Storage'),
                  subtitle: Text('Tokens validated and stored locally'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}