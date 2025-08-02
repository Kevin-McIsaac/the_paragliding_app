import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/igc_import_service.dart';
import '../../data/models/flight.dart';

class IgcImportScreen extends StatefulWidget {
  const IgcImportScreen({super.key});

  @override
  State<IgcImportScreen> createState() => _IgcImportScreenState();
}

class _IgcImportScreenState extends State<IgcImportScreen> {
  final IgcImportService _importService = IgcImportService();
  bool _isLoading = false;
  List<String> _selectedFilePaths = [];
  String? _errorMessage;
  List<Flight> _importedFlights = [];
  Map<String, String> _importErrors = {};
  String? _currentlyProcessingFile;

  Future<void> _pickIgcFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['igc', 'IGC'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final validPaths = result.files
            .where((file) => file.path != null)
            .map((file) => file.path!)
            .toList();
        
        setState(() {
          _selectedFilePaths = validPaths;
          _errorMessage = null;
          _importErrors.clear();
          _importedFlights.clear();
          _currentlyProcessingFile = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error selecting files: $e';
      });
    }
  }

  Future<void> _importFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _importErrors.clear();
      _importedFlights.clear();
    });

    int successCount = 0;
    int failureCount = 0;

    for (final filePath in _selectedFilePaths) {
      setState(() {
        _currentlyProcessingFile = filePath.split('/').last;
      });
      
      try {
        final flight = await _importService.importIgcFile(filePath);
        setState(() {
          _importedFlights.add(flight);
        });
        successCount++;
      } catch (e) {
        setState(() {
          _importErrors[filePath.split('/').last] = e.toString();
        });
        failureCount++;
      }
    }

    setState(() {
      _currentlyProcessingFile = null;
    });

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(failureCount == 0 ? 'Import Successful' : 'Import Complete'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Imported $successCount flight${successCount != 1 ? 's' : ''} successfully!'),
                if (failureCount > 0) ...[
                  const SizedBox(height: 8),
                  Text('$failureCount file${failureCount != 1 ? 's' : ''} failed to import.'),
                ],
                const SizedBox(height: 16),
                if (_importedFlights.isNotEmpty) ...[
                  const Text('Successfully imported:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._importedFlights.map((flight) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${_formatDate(flight.date)} - ${flight.duration} min'),
                  )),
                ],
                if (_importErrors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Failed imports:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 8),
                  ..._importErrors.entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${entry.key}: ${entry.value}', style: const TextStyle(color: Colors.red)),
                  )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (successCount > 0) {
                  Navigator.of(context).pop(true); // Return to flight list
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import IGC File'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'IGC File Import',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Import flight data from IGC files recorded by your flight instrument. You can select multiple files at once.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickIgcFiles,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Select IGC Files'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            if (_selectedFilePaths.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.insert_drive_file, size: 48),
                      title: Text('Selected Files (${_selectedFilePaths.length})'),
                      trailing: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _selectedFilePaths.clear();
                            _importErrors.clear();
                            _importedFlights.clear();
                            _currentlyProcessingFile = null;
                          });
                        },
                      ),
                    ),
                    if (_selectedFilePaths.length <= 5) 
                      ...(_selectedFilePaths.map((path) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.description, size: 20),
                        title: Text(
                          path.split('/').last,
                          style: const TextStyle(fontSize: 12),
                        ),
                      )))
                    else ...[
                      ...(_selectedFilePaths.take(3).map((path) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.description, size: 20),
                        title: Text(
                          path.split('/').last,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ))),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.more_horiz, size: 20),
                        title: Text(
                          'and ${_selectedFilePaths.length - 3} more files...',
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_isLoading && _currentlyProcessingFile != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Text('Processing: $_currentlyProcessingFile'),
                      const SizedBox(height: 4),
                      Text(
                        'Imported ${_importedFlights.length} of ${_selectedFilePaths.length} files',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const Spacer(),

            if (_selectedFilePaths.isNotEmpty)
              ElevatedButton(
                onPressed: _isLoading ? null : _importFiles,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        _selectedFilePaths.length == 1 
                          ? 'Import Flight' 
                          : 'Import ${_selectedFilePaths.length} Flights',
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}