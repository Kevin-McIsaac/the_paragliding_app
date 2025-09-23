import 'package:flutter/material.dart';
import '../../services/airspace_country_service.dart';
import '../../data/models/airspace_country_models.dart';

class AirspaceCountrySelector extends StatefulWidget {
  const AirspaceCountrySelector({super.key});

  @override
  State<AirspaceCountrySelector> createState() => _AirspaceCountrySelectorState();
}

class _AirspaceCountrySelectorState extends State<AirspaceCountrySelector> {
  final AirspaceCountryService _countryService = AirspaceCountryService.instance;

  String? _downloadingCountry;
  double? _downloadProgress;
  late Future<List<CountrySelectionModel>> _countriesFuture;

  @override
  void initState() {
    super.initState();
    _refreshCountries();
  }

  /// Refresh the country list data
  void _refreshCountries() {
    _countriesFuture = _buildCountryList();
  }

  Future<List<CountrySelectionModel>> _buildCountryList() async {
    // Get selected countries and metadata in real-time
    final selectedCodes = await _countryService.getSelectedCountries();
    final metadata = await _countryService.getCountryMetadata();

    // Build country models
    final countries = <CountrySelectionModel>[];
    for (final entry in AirspaceCountryService.availableCountries.entries) {
      final code = entry.key;
      final info = entry.value;
      final meta = metadata[code];
      final isDownloaded = meta != null;
      // Only consider a country selected if it has data in the database AND is in the selected list
      final isSelected = isDownloaded && selectedCodes.contains(code);

      DownloadStatus status;
      if (_downloadingCountry == code) {
        status = DownloadStatus.downloading;
      } else if (isDownloaded) {
        if (meta.needsUpdate) {
          status = DownloadStatus.updateAvailable;
        } else {
          status = DownloadStatus.downloaded;
        }
      } else {
        status = DownloadStatus.notDownloaded;
      }

      countries.add(CountrySelectionModel(
        info: info,
        isSelected: isSelected,
        isDownloaded: isDownloaded,
        status: status,
        downloadProgress: _downloadingCountry == code ? _downloadProgress : null,
        metadata: meta,
      ));
    }

    // Sort countries: selected first, then by name
    countries.sort((a, b) {
      if (a.isSelected != b.isSelected) {
        return a.isSelected ? -1 : 1;
      }
      return a.info.name.compareTo(b.info.name);
    });

    return countries;
  }

  Future<void> _toggleCountry(CountrySelectionModel country) async {
    if (_downloadingCountry != null) return; // Don't allow changes during download

    if (country.isSelected) {
      // Deselect and optionally delete
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove Country'),
          content: Text(
            country.isDownloaded
                ? 'Do you want to remove ${country.info.name} and delete its cached data?'
                : 'Do you want to remove ${country.info.name} from your selection?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            if (country.isDownloaded)
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Keep Data'),
              ),
            TextButton(
              onPressed: () async {
                if (country.isDownloaded) {
                  await _countryService.deleteCountryData(country.info.code);
                }
                if (mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              child: Text(
                country.isDownloaded ? 'Delete Data' : 'Remove',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (shouldDelete == true) {
        final selected = await _countryService.getSelectedCountries();
        selected.remove(country.info.code);
        await _countryService.setSelectedCountries(selected);
        setState(() {
          _refreshCountries();
        });
      }
    } else {
      // Select and download if needed
      final selected = await _countryService.getSelectedCountries();
      selected.add(country.info.code);
      await _countryService.setSelectedCountries(selected);

      if (!country.isDownloaded) {
        await _downloadCountry(country.info.code);
      } else {
        setState(() {
          _refreshCountries();
        });
      }
    }
  }

  Future<void> _downloadCountry(String countryCode) async {
    setState(() {
      _downloadingCountry = countryCode;
      _downloadProgress = 0.0;
    });

    try {
      final result = await _countryService.downloadCountryData(
        countryCode,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              // NOTE: Do NOT call _refreshCountries() here - this would cause
              // hundreds of database queries during download progress updates
            });
          }
        },
      );

      if (result.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Downloaded ${result.airspaceCount} airspaces for ${AirspaceCountryService.availableCountries[countryCode]?.name}',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to download: ${result.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      setState(() {
        _downloadingCountry = null;
        _downloadProgress = null;
      });
      setState(() {
        _refreshCountries();
      });
    }
  }

  Future<void> _updateCountry(CountrySelectionModel country) async {
    if (await _countryService.checkForUpdate(country.info.code)) {
      await _downloadCountry(country.info.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CountrySelectionModel>>(
      future: _countriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Error loading countries: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final countries = snapshot.data ?? [];

        return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Airspace Countries',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Select countries to download their airspace data for offline use',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: countries.length,
            itemBuilder: (context, index) {
              final country = countries[index];
              return _buildCountryTile(country);
            },
          ),
        ),
        ],
      );
      },
    );
  }

  Widget _buildCountryTile(CountrySelectionModel country) {
    final isDownloading = _downloadingCountry == country.info.code;

    return ListTile(
      dense: true, // Make tiles more compact
      visualDensity: VisualDensity.compact, // Reduce vertical padding
      contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0.0), // Reduce padding
      leading: Checkbox(
        value: country.isSelected,
        onChanged: isDownloading ? null : (_) => _toggleCountry(country),
      ),
      title: Text(
        country.info.name,
        style: const TextStyle(fontSize: 14), // Slightly smaller font
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getStatusText(country),
            style: const TextStyle(fontSize: 12), // Smaller subtitle font
          ),
          if (isDownloading && _downloadProgress != null)
            LinearProgressIndicator(
              value: _downloadProgress,
              minHeight: 2,
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (country.status == DownloadStatus.updateAvailable)
            IconButton(
              iconSize: 20, // Smaller icons
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.update, color: Colors.orange),
              onPressed: () => _updateCountry(country),
              tooltip: 'Update available',
            ),
          if (country.isDownloaded)
            IconButton(
              iconSize: 20, // Smaller icons
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Country Data'),
                    content: Text(
                      'Delete all airspace data for ${country.info.name}?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await _countryService.deleteCountryData(country.info.code);
                  setState(() {
                    _refreshCountries();
                  });
                }
              },
              tooltip: 'Delete data',
            ),
          if (!country.isDownloaded && country.isSelected && !isDownloading)
            IconButton(
              iconSize: 20, // Smaller icons
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.download, color: Colors.blue),
              onPressed: () => _downloadCountry(country.info.code),
              tooltip: 'Download',
            ),
        ],
      ),
    );
  }

  String _getStatusText(CountrySelectionModel country) {
    if (_downloadingCountry == country.info.code) {
      return 'Downloading... ${(_downloadProgress ?? 0 * 100).toStringAsFixed(0)}%';
    }

    if (country.isDownloaded) {
      final meta = country.metadata!;
      final ageText = _getAgeText(meta.downloadTime);

      if (country.status == DownloadStatus.updateAvailable) {
        return '${meta.airspaceCount} airspaces • Update available';
      }
      return '${meta.airspaceCount} airspaces • $ageText';
    }

    return 'Not downloaded';
  }

  String _getAgeText(DateTime downloadTime) {
    final age = DateTime.now().difference(downloadTime);

    if (age.inDays > 30) {
      return '${age.inDays ~/ 30} month${age.inDays ~/ 30 > 1 ? 's' : ''} ago';
    } else if (age.inDays > 0) {
      return '${age.inDays} day${age.inDays > 1 ? 's' : ''} ago';
    } else if (age.inHours > 0) {
      return '${age.inHours} hour${age.inHours > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
}