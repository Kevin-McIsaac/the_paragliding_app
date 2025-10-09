import 'package:flutter/material.dart';
import '../../data/models/flight.dart';

/// Actions that can be taken when a duplicate flight is found
enum DuplicateAction {
  skip,
  skipAll,
  replace,
  replaceAll,
}

/// Dialog shown when a duplicate flight is detected during IGC import
class DuplicateFlightDialog extends StatelessWidget {
  final Flight existingFlight;
  final String newFileName;
  final DateTime newFlightDate;
  final String newFlightTime;
  final int newFlightDuration;
  final bool isFilenameDuplicate;

  const DuplicateFlightDialog({
    super.key,
    required this.existingFlight,
    required this.newFileName,
    required this.newFlightDate,
    required this.newFlightTime,
    required this.newFlightDuration,
    this.isFilenameDuplicate = false,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.warning_amber,
            color: Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 8),
          const Text('Duplicate Flight Found'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFilenameDuplicate 
                ? 'This file has already been imported.'
                : 'A flight with the same date and launch time already exists.',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            
            // Existing flight details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Existing Flight:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildFlightDetailRow('Date:', _formatDate(existingFlight.date)),
                  _buildFlightDetailRow('Launch Time:', existingFlight.effectiveLaunchTime),
                  _buildFlightDetailRow('Duration:', '${existingFlight.effectiveDuration} minutes'),
                  if (existingFlight.maxAltitude != null)
                    _buildFlightDetailRow('Max Altitude:', '${existingFlight.maxAltitude!.round()}m'),
                  _buildFlightDetailRow('Source:', existingFlight.source),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // New flight details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Color.alphaBlend(
                        Colors.green.withValues(alpha: 0.15),
                        Theme.of(context).colorScheme.surface,
                      )
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.green.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New IGC File:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.green.shade400
                          : Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildFlightDetailRow('File:', newFileName),
                  _buildFlightDetailRow('Date:', _formatDate(newFlightDate)),
                  _buildFlightDetailRow('Launch Time:', newFlightTime),
                  _buildFlightDetailRow('Duration:', '$newFlightDuration minutes'),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            Text(
              'What would you like to do?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Skip button
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(DuplicateAction.skip),
          icon: const Icon(Icons.skip_next, size: 20),
          label: const Text('Skip'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade600,
          ),
        ),
        
        // Skip All button
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(DuplicateAction.skipAll),
          icon: const Icon(Icons.skip_next, size: 20),
          label: const Text('Skip All'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade600,
          ),
        ),
        
        // Replace button
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(DuplicateAction.replace),
          icon: const Icon(Icons.refresh, size: 20),
          label: const Text('Replace'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.orange.shade700,
          ),
        ),
        
        // Replace All button
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(DuplicateAction.replaceAll),
          icon: const Icon(Icons.refresh, size: 20),
          label: const Text('Replace All'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.orange.shade700,
            backgroundColor: Colors.orange.shade50,
          ),
        ),
      ],
    );
  }

  Widget _buildFlightDetailRow(String label, String value) {
    return Builder(
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}