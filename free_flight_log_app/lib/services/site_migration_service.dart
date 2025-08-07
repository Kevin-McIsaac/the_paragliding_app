import '../data/repositories/site_repository.dart';
import '../data/models/site.dart';
import '../services/logging_service.dart';
import 'site_matching_service.dart';
import '../core/dependency_injection.dart';

/// Service for migrating existing sites to populate country field
class SiteMigrationService {
  final SiteRepository _siteRepository = serviceLocator<SiteRepository>();
  final SiteMatchingService _siteMatchingService = SiteMatchingService.instance;

  /// Migrate all sites that are missing country information
  /// Uses the ParaglidingEarth API to lookup location information
  Future<SiteMigrationResult> migrateExistingSites() async {
    final result = SiteMigrationResult();
    
    try {
      // Ensure site matching service is initialized
      if (!_siteMatchingService.isReady) {
        await _siteMatchingService.initialize();
      }
      
      // Get all sites that need location info
      final sitesToMigrate = await _siteRepository.getSitesWithoutLocationInfo();
      result.totalSites = sitesToMigrate.length;
      
      if (sitesToMigrate.isEmpty) {
        result.message = 'All sites already have location information';
        return result;
      }
      
      LoggingService.info('SiteMigrationService: Found ${sitesToMigrate.length} sites needing location info');
      
      for (final site in sitesToMigrate) {
        try {
          // Try to match with a paragliding site to get country/state info
          final matchedSite = await _siteMatchingService.findNearestSite(
            site.latitude,
            site.longitude,
            maxDistance: 1000, // 1km for migration
            preferredType: 'launch',
          );
          
          if (matchedSite != null && matchedSite.country != null) {
            // Update the site with country information
            await _siteRepository.updateSiteLocationInfo(
              site.id!,
              matchedSite.country,
            );
            
            result.updatedSites++;
            LoggingService.info('SiteMigrationService: Updated "${site.name}" with country "${matchedSite.country}"');
          } else {
            result.skippedSites++;
            LoggingService.info('SiteMigrationService: No country info found for "${site.name}"');
          }
        } catch (e) {
          result.errorSites++;
          LoggingService.error('SiteMigrationService: Error processing "${site.name}"', e);
        }
        
        // Small delay to avoid overwhelming the API
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      result.message = 'Migration completed: ${result.updatedSites} updated, ${result.skippedSites} skipped, ${result.errorSites} errors';
      
    } catch (e) {
      result.message = 'Migration failed: $e';
      LoggingService.error('SiteMigrationService: Fatal error', e);
    }
    
    return result;
  }
}

/// Result of the site migration process
class SiteMigrationResult {
  int totalSites = 0;
  int updatedSites = 0;
  int skippedSites = 0;
  int errorSites = 0;
  String message = '';
  
  bool get hasUpdates => updatedSites > 0;
  bool get isComplete => (updatedSites + skippedSites + errorSites) == totalSites;
}