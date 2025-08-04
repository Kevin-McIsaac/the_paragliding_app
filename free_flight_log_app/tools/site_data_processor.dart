import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../lib/services/kml_parser.dart';
import '../lib/data/models/paragliding_site.dart';

/// Development tool for downloading and processing KML files from Paraglidingearth.com
/// This creates a curated list of popular paragliding sites for the app.
class SiteDataProcessor {
  static const String baseUrl = 'https://www.paraglidingearth.com/api/sites/export';
  static const int maxSites = 1000; // Number of most popular sites to include

  /// URLs for regional KML files from Paraglidingearth.com
  static const Map<String, String> regionalUrls = {
    'europe': '$baseUrl/europe.kml',
    'north_america': '$baseUrl/north_america.kml',
    'south_america': '$baseUrl/south_america.kml',
    'asia': '$baseUrl/asia.kml',
    'africa': '$baseUrl/africa.kml',
    'oceania': '$baseUrl/oceania.kml',
  };

  /// Download KML files from Paraglidingearth.com
  static Future<void> downloadKmlFiles(String outputDir) async {
    final directory = Directory(outputDir);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    print('Downloading KML files from Paraglidingearth.com...');

    for (final entry in regionalUrls.entries) {
      final region = entry.key;
      final url = entry.value;
      final outputPath = path.join(outputDir, '$region.kml');

      try {
        print('Downloading $region from $url...');
        final response = await http.get(Uri.parse(url));
        
        if (response.statusCode == 200) {
          final file = File(outputPath);
          await file.writeAsBytes(response.bodyBytes);
          print('✓ Downloaded $region (${(response.bodyBytes.length / 1024).round()} KB)');
        } else {
          print('✗ Failed to download $region: HTTP ${response.statusCode}');
        }
      } catch (e) {
        print('✗ Error downloading $region: $e');
      }

      // Be nice to the server - wait between requests
      await Future.delayed(const Duration(seconds: 2));
    }

    print('Download complete!\n');
  }

  /// Process all KML files and extract the most popular sites
  static Future<List<ParaglidingSite>> processKmlFiles(String kmlDir) async {
    final allSites = <ParaglidingSite>[];
    final directory = Directory(kmlDir);

    if (!directory.existsSync()) {
      print('KML directory does not exist: $kmlDir');
      return allSites;
    }

    print('Processing KML files...');

    // Process each regional KML file
    for (final region in regionalUrls.keys) {
      final kmlFile = File(path.join(kmlDir, '$region.kml'));
      
      if (kmlFile.existsSync()) {
        print('Processing $region.kml...');
        try {
          final sites = await KmlParser.parseKmlFile(kmlFile.path);
          allSites.addAll(sites);
          print('✓ Extracted ${sites.length} sites from $region');
        } catch (e) {
          print('✗ Error processing $region.kml: $e');
        }
      } else {
        print('✗ File not found: $region.kml');
      }
    }

    print('Total sites extracted: ${allSites.length}');

    // Filter to most popular sites
    final popularSites = KmlParser.filterPopularSites(allSites, maxSites);
    print('Filtered to ${popularSites.length} most popular sites\n');

    return popularSites;
  }

  /// Generate JSON asset file for the app
  static Future<void> generateAssetFile(
    List<ParaglidingSite> sites, 
    String outputPath,
  ) async {
    print('Generating JSON asset file...');

    // Convert sites to JSON
    final jsonList = sites.map((site) => site.toJson()).toList();
    
    // Add metadata
    final data = {
      'version': '1.0',
      'generated': DateTime.now().toIso8601String(),
      'source': 'paraglidingearth.com',
      'total_sites': sites.length,
      'sites': jsonList,
    };

    // Write to file with pretty formatting
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final file = File(outputPath);
    await file.writeAsString(jsonString);

    print('✓ Generated ${path.basename(outputPath)} (${(jsonString.length / 1024).round()} KB)');
    print('Asset file ready for: assets/popular_paragliding_sites.json\n');
  }

  /// Print statistics about the processed sites
  static void printStatistics(List<ParaglidingSite> sites) {
    print('=== SITE STATISTICS ===');
    print('Total sites: ${sites.length}');
    
    // By type
    final launches = sites.where((s) => s.siteType == 'launch' || s.siteType == 'both').length;
    final landings = sites.where((s) => s.siteType == 'landing' || s.siteType == 'both').length;
    print('Launch sites: $launches');
    print('Landing sites: $landings');
    
    // By country
    final countryCount = <String, int>{};
    for (final site in sites) {
      if (site.country != null) {
        countryCount[site.country!] = (countryCount[site.country!] ?? 0) + 1;
      }
    }
    
    print('\nTop 10 countries:');
    final sortedCountries = countryCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    for (int i = 0; i < 10 && i < sortedCountries.length; i++) {
      final entry = sortedCountries[i];
      print('  ${entry.key}: ${entry.value} sites');
    }
    
    // By rating
    final ratedSites = sites.where((s) => s.rating > 0).length;
    print('\nRated sites: $ratedSites');
    
    if (ratedSites > 0) {
      final avgRating = sites
          .where((s) => s.rating > 0)
          .map((s) => s.rating)
          .reduce((a, b) => a + b) / ratedSites;
      print('Average rating: ${avgRating.toStringAsFixed(1)} stars');
    }
    
    // Popular sites (top 10)
    final topSites = sites.take(10).toList();
    print('\nTop 10 most popular sites:');
    for (int i = 0; i < topSites.length; i++) {
      final site = topSites[i];
      final rating = site.rating > 0 ? ' (${site.rating}⭐)' : '';
      final location = site.country != null ? ', ${site.country}' : '';
      print('  ${i + 1}. ${site.name}$location$rating');
    }
    
    print('');
  }

  /// Main processing pipeline
  static Future<void> processAll({
    String? kmlDir,
    String? outputPath,
    bool downloadFirst = false,
  }) async {
    final workingDir = kmlDir ?? './kml_downloads';
    final assetPath = outputPath ?? './popular_paragliding_sites.json';

    try {
      // Step 1: Download KML files if requested
      if (downloadFirst) {
        await downloadKmlFiles(workingDir);
      }

      // Step 2: Process KML files
      final sites = await processKmlFiles(workingDir);
      
      if (sites.isEmpty) {
        print('No sites were processed. Check KML files and try again.');
        return;
      }

      // Step 3: Generate asset file
      await generateAssetFile(sites, assetPath);

      // Step 4: Print statistics
      printStatistics(sites);

      print('✅ Processing complete!');
      print('Copy the generated file to: assets/popular_paragliding_sites.json');
      
    } catch (e) {
      print('❌ Error during processing: $e');
    }
  }
}

/// Command-line interface for the site data processor
void main(List<String> arguments) async {
  print('🪂 Paragliding Site Data Processor');
  print('=====================================\n');

  // Parse command line arguments
  bool downloadFirst = arguments.contains('--download');
  String? kmlDir = _getArgumentValue(arguments, '--kml-dir');
  String? outputPath = _getArgumentValue(arguments, '--output');

  if (arguments.contains('--help') || arguments.contains('-h')) {
    _printUsage();
    return;
  }

  // Run the processor
  await SiteDataProcessor.processAll(
    kmlDir: kmlDir,
    outputPath: outputPath,
    downloadFirst: downloadFirst,
  );
}

String? _getArgumentValue(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index != -1 && index + 1 < args.length) {
    return args[index + 1];
  }
  return null;
}

void _printUsage() {
  print('''
Usage: dart run tools/site_data_processor.dart [options]

Options:
  --download              Download KML files from paraglidingearth.com first
  --kml-dir <path>       Directory containing KML files (default: ./kml_downloads)
  --output <path>        Output path for JSON file (default: ./popular_paragliding_sites.json)
  --help, -h             Show this help message

Examples:
  # Download and process all in one go
  dart run tools/site_data_processor.dart --download

  # Process existing KML files
  dart run tools/site_data_processor.dart --kml-dir ./my_kml_files

  # Custom output location
  dart run tools/site_data_processor.dart --output ./assets/sites.json

Note: You'll need to add the http package to dev_dependencies to use the download feature.
''');
}