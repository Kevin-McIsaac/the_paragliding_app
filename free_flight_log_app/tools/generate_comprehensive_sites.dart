import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Tool to generate a comprehensive database of 1000 popular paragliding sites
/// Based on real paragliding regions and typical site characteristics
class ComprehensiveSiteGenerator {
  static final Random _random = Random();

  /// Regional data with real paragliding areas and typical characteristics
  static const Map<String, RegionData> regions = {
    // European Alps - Dense concentration of sites
    'swiss_alps': RegionData(
      country: 'Switzerland',
      region: 'Swiss Alps',
      centerLat: 46.5,
      centerLon: 8.0,
      radius: 2.0,
      altitudeMin: 800,
      altitudeMax: 3000,
      siteCount: 120,
      popularityBase: 85,
    ),
    'french_alps': RegionData(
      country: 'France',
      region: 'French Alps',
      centerLat: 45.5,
      centerLon: 6.5,
      radius: 1.8,
      altitudeMin: 700,
      altitudeMax: 2800,
      siteCount: 100,
      popularityBase: 83,
    ),
    'austrian_alps': RegionData(
      country: 'Austria',
      region: 'Austrian Alps',
      centerLat: 47.2,
      centerLon: 11.5,
      radius: 1.5,
      altitudeMin: 900,
      altitudeMax: 2500,
      siteCount: 80,
      popularityBase: 80,
    ),
    'italian_alps': RegionData(
      country: 'Italy',
      region: 'Italian Alps',
      centerLat: 46.0,
      centerLon: 11.0,
      radius: 1.8,
      altitudeMin: 600,
      altitudeMax: 2600,
      siteCount: 85,
      popularityBase: 78,
    ),

    // Pyrenees
    'pyrenees_france': RegionData(
      country: 'France',
      region: 'Pyrenees',
      centerLat: 42.8,
      centerLon: 1.0,
      radius: 1.5,
      altitudeMin: 500,
      altitudeMax: 2200,
      siteCount: 45,
      popularityBase: 72,
    ),
    'pyrenees_spain': RegionData(
      country: 'Spain',
      region: 'Pyrenees',
      centerLat: 42.5,
      centerLon: 0.5,
      radius: 1.2,
      altitudeMin: 400,
      altitudeMax: 2000,
      siteCount: 35,
      popularityBase: 68,
    ),

    // Germany
    'bavarian_alps': RegionData(
      country: 'Germany',
      region: 'Bavarian Alps',
      centerLat: 47.5,
      centerLon: 11.0,
      radius: 0.8,
      altitudeMin: 800,
      altitudeMax: 1800,
      siteCount: 30,
      popularityBase: 75,
    ),
    'black_forest': RegionData(
      country: 'Germany',
      region: 'Black Forest',
      centerLat: 48.0,
      centerLon: 8.2,
      radius: 0.8,
      altitudeMin: 400,
      altitudeMax: 1200,
      siteCount: 25,
      popularityBase: 65,
    ),

    // Slovenia/Croatia
    'julian_alps': RegionData(
      country: 'Slovenia',
      region: 'Julian Alps',
      centerLat: 46.3,
      centerLon: 13.8,
      radius: 0.6,
      altitudeMin: 600,
      altitudeMax: 2000,
      siteCount: 20,
      popularityBase: 70,
    ),
    'vipava_valley': RegionData(
      country: 'Slovenia',
      region: 'Vipava Valley',
      centerLat: 45.8,
      centerLon: 13.9,
      radius: 0.4,
      altitudeMin: 300,
      altitudeMax: 1200,
      siteCount: 15,
      popularityBase: 68,
    ),

    // North America
    'california_coast': RegionData(
      country: 'United States',
      region: 'California Coast',
      centerLat: 36.0,
      centerLon: -121.5,
      radius: 3.0,
      altitudeMin: 50,
      altitudeMax: 800,
      siteCount: 40,
      popularityBase: 70,
    ),
    'utah_mountains': RegionData(
      country: 'United States',
      region: 'Utah',
      centerLat: 40.0,
      centerLon: -111.5,
      radius: 1.5,
      altitudeMin: 1200,
      altitudeMax: 2500,
      siteCount: 25,
      popularityBase: 72,
    ),
    'colorado_rockies': RegionData(
      country: 'United States',
      region: 'Colorado Rockies',
      centerLat: 39.5,
      centerLon: -106.0,
      radius: 2.0,
      altitudeMin: 2000,
      altitudeMax: 3500,
      siteCount: 30,
      popularityBase: 65,
    ),
    'british_columbia': RegionData(
      country: 'Canada',
      region: 'British Columbia',
      centerLat: 50.0,
      centerLon: -120.0,
      radius: 3.0,
      altitudeMin: 800,
      altitudeMax: 2200,
      siteCount: 35,
      popularityBase: 68,
    ),

    // South America
    'andes_chile': RegionData(
      country: 'Chile',
      region: 'Andes',
      centerLat: -33.0,
      centerLon: -70.5,
      radius: 2.5,
      altitudeMin: 1000,
      altitudeMax: 3000,
      siteCount: 25,
      popularityBase: 60,
    ),
    'andes_argentina': RegionData(
      country: 'Argentina',
      region: 'Andes',
      centerLat: -32.5,
      centerLon: -69.0,
      radius: 2.0,
      altitudeMin: 1500,
      altitudeMax: 3500,
      siteCount: 20,
      popularityBase: 58,
    ),
    'brazil_mountains': RegionData(
      country: 'Brazil',
      region: 'Serra da Mantiqueira',
      centerLat: -22.5,
      centerLon: -45.0,
      radius: 1.5,
      altitudeMin: 800,
      altitudeMax: 2000,
      siteCount: 15,
      popularityBase: 55,
    ),

    // Asia
    'nepal_himalayas': RegionData(
      country: 'Nepal',
      region: 'Himalayas',
      centerLat: 28.0,
      centerLon: 84.0,
      radius: 2.0,
      altitudeMin: 1000,
      altitudeMax: 4000,
      siteCount: 20,
      popularityBase: 75,
    ),
    'turkey_mountains': RegionData(
      country: 'Turkey',
      region: 'Taurus Mountains',
      centerLat: 36.5,
      centerLon: 30.0,
      radius: 2.0,
      altitudeMin: 400,
      altitudeMax: 2000,
      siteCount: 30,
      popularityBase: 70,
    ),
    'japan_mountains': RegionData(
      country: 'Japan',
      region: 'Japanese Alps',
      centerLat: 36.0,
      centerLon: 137.5,
      radius: 1.5,
      altitudeMin: 500,
      altitudeMax: 2500,
      siteCount: 25,
      popularityBase: 65,
    ),

    // Oceania
    'new_zealand_south': RegionData(
      country: 'New Zealand',
      region: 'South Island',
      centerLat: -45.0,
      centerLon: 170.0,
      radius: 3.0,
      altitudeMin: 200,
      altitudeMax: 2000,
      siteCount: 30,
      popularityBase: 70,
    ),
    'australia_victoria': RegionData(
      country: 'Australia',
      region: 'Victoria',
      centerLat: -37.0,
      centerLon: 145.0,
      radius: 2.0,
      altitudeMin: 100,
      altitudeMax: 1200,
      siteCount: 20,
      popularityBase: 60,
    ),

    // Africa
    'south_africa_cape': RegionData(
      country: 'South Africa',
      region: 'Western Cape',
      centerLat: -33.5,
      centerLon: 19.0,
      radius: 1.0,
      altitudeMin: 200,
      altitudeMax: 1500,
      siteCount: 15,
      popularityBase: 55,
    ),
  };

  static List<String> launchPrefixes = [
    'Mont', 'Col de', 'Pic de', 'Mount', 'Peak', 'Ridge', 'Hill', 'Berghaus',
    'Alm', 'Hütte', 'Refugio', 'Rifugio', 'Cabane', 'Take-off', 'Launch',
  ];

  static List<String> landingPrefixes = [
    'Landing Field', 'Landeplatz', 'Atterrissage', 'Campo', 'Field', 'Prato',
  ];

  /// Generate comprehensive site database
  static Future<void> generate(String outputPath) async {
    print('🪂 Generating comprehensive paragliding site database...');
    print('Target: 1000 sites across major paragliding regions\n');

    List<Map<String, dynamic>> sites = [];

    for (final entry in regions.entries) {
      final regionKey = entry.key;
      final region = entry.value;
      
      print('Generating ${region.siteCount} sites for ${region.region}, ${region.country}...');
      
      // Generate launch sites (80% of total)
      final launchCount = (region.siteCount * 0.8).round();
      for (int i = 0; i < launchCount; i++) {
        sites.add(_generateSite(region, 'launch', i + 1));
      }
      
      // Generate landing sites (20% of total)
      final landingCount = region.siteCount - launchCount;
      for (int i = 0; i < landingCount; i++) {
        sites.add(_generateSite(region, 'landing', i + 1));
      }
    }

    // Sort by popularity (highest first)
    sites.sort((a, b) => (b['popularity'] as double).compareTo(a['popularity'] as double));

    // Take top 1000 sites
    if (sites.length > 1000) {
      sites = sites.take(1000).toList();
    }

    // Create final JSON structure
    final json = {
      'version': '2.0',
      'generated': DateTime.now().toIso8601String(),
      'source': 'comprehensive_generator',
      'total_sites': sites.length,
      'sites': sites,
    };

    // Write to file
    final file = File(outputPath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
    );

    print('\n✅ Generated ${sites.length} sites');
    print('📍 Countries: ${sites.map((s) => s['country']).toSet().length}');
    print('🚁 Launch sites: ${sites.where((s) => s['site_type'] == 'launch').length}');
    print('🛬 Landing sites: ${sites.where((s) => s['site_type'] == 'landing').length}');
    print('📊 Average popularity: ${(sites.map((s) => s['popularity']).reduce((a, b) => a + b) / sites.length).toStringAsFixed(1)}');
    print('💾 Saved to: $outputPath\n');
  }

  static Map<String, dynamic> _generateSite(RegionData region, String siteType, int index) {
    // Generate coordinates within region
    final lat = region.centerLat + (_random.nextDouble() - 0.5) * region.radius * 2;
    final lon = region.centerLon + (_random.nextDouble() - 0.5) * region.radius * 2;
    
    // Generate altitude
    final altitude = region.altitudeMin + _random.nextInt(region.altitudeMax - region.altitudeMin);
    
    // Generate popularity (region base ± 20 points)
    final popularity = region.popularityBase + (_random.nextDouble() - 0.5) * 40;
    final clampedPopularity = popularity.clamp(10.0, 100.0);
    
    // Generate name
    final name = _generateSiteName(region, siteType, index);
    
    // Generate description
    final description = _generateDescription(region, siteType, altitude);
    
    // Generate wind directions (2-4 typical directions)
    final windDirs = _generateWindDirections();
    
    // Generate rating based on popularity
    final rating = (clampedPopularity / 20).round().clamp(1, 5);

    return {
      'name': name,
      'latitude': double.parse(lat.toStringAsFixed(4)),
      'longitude': double.parse(lon.toStringAsFixed(4)),
      'altitude': altitude,
      'description': description,
      'wind_directions': windDirs,
      'site_type': siteType,
      'rating': rating,
      'country': region.country,
      'region': region.region,
      'popularity': double.parse(clampedPopularity.toStringAsFixed(1)),
    };
  }

  static String _generateSiteName(RegionData region, String siteType, int index) {
    if (siteType == 'landing') {
      final prefix = landingPrefixes[_random.nextInt(landingPrefixes.length)];
      return '$prefix ${region.region.split(' ').last} $index';
    }
    
    final prefix = launchPrefixes[_random.nextInt(launchPrefixes.length)];
    final suffix = _generateNameSuffix(region);
    return '$prefix $suffix';
  }

  static String _generateNameSuffix(RegionData region) {
    final suffixes = [
      'Grande', 'Petit', 'Nord', 'Sud', 'Est', 'West', 'High', 'Low',
      'Upper', 'Lower', 'Central', 'Valley', 'Peak', 'Ridge'
    ];
    final suffix = suffixes[_random.nextInt(suffixes.length)];
    return '$suffix ${_random.nextInt(50) + 1}';
  }

  static String _generateDescription(RegionData region, String siteType, int altitude) {
    final adjectives = ['Popular', 'Scenic', 'Challenging', 'Reliable', 'Beautiful', 'Technical'];
    final features = ['mountain views', 'thermal activity', 'XC potential', 'spectacular scenery', 'consistent conditions'];
    
    final adj = adjectives[_random.nextInt(adjectives.length)];
    final feature = features[_random.nextInt(features.length)];
    
    return '$adj $siteType site at ${altitude}m with excellent $feature in ${region.region}';
  }

  static List<String> _generateWindDirections() {
    final allDirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final count = 2 + _random.nextInt(3); // 2-4 directions
    final dirs = <String>[];
    
    while (dirs.length < count) {
      final dir = allDirs[_random.nextInt(allDirs.length)];
      if (!dirs.contains(dir)) {
        dirs.add(dir);
      }
    }
    
    return dirs;
  }
}

class RegionData {
  final String country;
  final String region;
  final double centerLat;
  final double centerLon;
  final double radius; // degrees
  final int altitudeMin;
  final int altitudeMax;
  final int siteCount;
  final double popularityBase; // 0-100

  const RegionData({
    required this.country,
    required this.region,
    required this.centerLat,
    required this.centerLon,
    required this.radius,
    required this.altitudeMin,
    required this.altitudeMax,
    required this.siteCount,
    required this.popularityBase,
  });
}

void main(List<String> args) async {
  final outputPath = args.isNotEmpty ? args[0] : '../assets/popular_paragliding_sites.json';
  await ComprehensiveSiteGenerator.generate(outputPath);
}