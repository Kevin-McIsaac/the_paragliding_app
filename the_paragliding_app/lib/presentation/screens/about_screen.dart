import 'package:flutter/material.dart';
import '../../utils/build_info.dart';
import '../widgets/common/app_attribution_link.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = 'loading...';
  String _gitCommit = 'loading...';
  String _gitBranch = 'loading...';

  @override
  void initState() {
    super.initState();
    _loadBuildInfo();
  }

  Future<void> _loadBuildInfo() async {
    final version = await BuildInfo.fullVersion;
    final commit = await BuildInfo.gitCommit;
    final branch = await BuildInfo.gitBranch;
    setState(() {
      _version = version;
      _gitCommit = commit;
      _gitBranch = branch;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 16, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.flight_takeoff,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'The Paragliding App',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Version $_version',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Build: $_gitCommit',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Branch: $_gitBranch',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'A mobile app for logging paraglider, hang glider, and microlight flights.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Contact Information Card (OSM Compliance)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.contact_mail,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Contact Information',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'For questions, feedback, or to report issues with map data:',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    AppAttributionLink.standard(
                      url: 'mailto:kevin.mcisaac+the.paragliding.app@gmail.com',
                      icon: Icons.email,
                      text: 'kevin.mcisaac+the.paragliding.app@gmail.com',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Package name: com.theparaglidingapp',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Map Data Attribution Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.map,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Map Data',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Map data and imagery are provided by:',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    AppAttributionLink.standard(
                      url: 'https://www.openstreetmap.org/copyright',
                      icon: Icons.public,
                      text: '© OpenStreetMap contributors',
                    ),
                    const SizedBox(height: 8),
                    AppAttributionLink.standard(
                      url: 'https://www.openstreetmap.org/fixthemap',
                      icon: Icons.edit,
                      text: 'Report map data issues',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Additional map providers:',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Esri World Imagery - Satellite and aerial imagery\n'
                      '• Esri World Topo - Topographic maps\n'
                      '• Google Maps - Street and terrain data\n'
                      '• Cesium Ion - 3D terrain and global base maps',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Site Data Attribution Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Site Data',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Paragliding site information is provided by:',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    AppAttributionLink.standard(
                      url: 'https://paraglidingearth.com',
                      icon: Icons.web,
                      text: 'ParaglidingEarth.com',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Weather Data Attribution Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.cloud,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Weather Data',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Weather information is provided by:',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Weather Forecasts:',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppAttributionLink.standard(
                      url: 'https://open-meteo.com',
                      icon: Icons.wb_sunny,
                      text: 'Open-Meteo - Free weather API',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Real-Time Weather Station Data:',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Observations from multiple global providers:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Aviation Weather Center
                    AppAttributionLink.compact(
                      url: 'https://aviationweather.gov',
                      icon: Icons.airplanemode_active,
                      text: 'Aviation Weather Center (METAR)',
                    ),
                    // National Weather Service
                    AppAttributionLink.compact(
                      url: 'https://www.weather.gov',
                      icon: Icons.cloud_queue,
                      text: 'National Weather Service (US)',
                    ),
                    // OpenWindMap
                    AppAttributionLink.compact(
                      url: 'https://www.openwindmap.org',
                      icon: Icons.air,
                      text: 'OpenWindMap Contributors',
                    ),
                    // FFVL
                    AppAttributionLink.compact(
                      url: 'https://federation.ffvl.fr',
                      icon: Icons.flight,
                      text: 'FFVL (French Free Flight Federation)',
                    ),
                    // Bureau of Meteorology
                    AppAttributionLink.compact(
                      url: 'https://www.bom.gov.au',
                      icon: Icons.wb_sunny,
                      text: 'Australian Bureau of Meteorology',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Privacy & Data Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.privacy_tip,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Privacy & Data',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your flight data stays on your device:',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Flight logs stored locally in SQLite database\n'
                      '• Track files stored on device storage\n'
                      '• No user accounts or cloud synchronization\n'
                      '• No flight data transmitted to external servers',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'External data services (fetched as needed):',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Map imagery: OpenStreetMap, Google Maps, Esri, Cesium Ion\n'
                      '• Paragliding sites: ParaglidingEarth API\n'
                      '• Airspace data: OpenAIP API\n'
                      '• Weather forecasts: Open-Meteo API\n'
                      '• Aviation Weather Center: Airport weather (METAR format)\n'
                      '• NWS stations: US National Weather Service (NOAA)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}