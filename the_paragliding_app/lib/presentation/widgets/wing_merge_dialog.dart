import 'package:flutter/material.dart';
import '../../data/models/wing.dart';
import '../../services/database_service.dart';
import '../../services/logging_service.dart';

class WingMergeDialog extends StatefulWidget {
  final List<Wing> wings;
  final Map<int, int> flightCounts;

  const WingMergeDialog({
    super.key,
    required this.wings,
    required this.flightCounts,
  });

  @override
  State<WingMergeDialog> createState() => _WingMergeDialogState();
}

class _WingMergeDialogState extends State<WingMergeDialog> {
  final Set<int> _selectedWingIds = {};
  bool _isProcessing = false;
  final DatabaseService _databaseService = DatabaseService.instance;

  void _toggleWingSelection(int wingId) {
    setState(() {
      if (_selectedWingIds.contains(wingId)) {
        _selectedWingIds.remove(wingId);
      } else {
        _selectedWingIds.add(wingId);
      }
    });
  }

  Future<void> _proceedToMerge() async {
    if (_selectedWingIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 2 wings to merge'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selectedWings = widget.wings
        .where((wing) => _selectedWingIds.contains(wing.id))
        .toList();

    // Show primary wing selection
    final primaryWing = await _showPrimaryWingSelection(selectedWings);
    if (primaryWing == null) return;

    // Show confirmation
    final confirmed = await _showMergeConfirmation(selectedWings, primaryWing);
    if (!confirmed) return;

    // Perform merge
    await _performMerge(selectedWings, primaryWing);
  }

  Future<Wing?> _showPrimaryWingSelection(List<Wing> selectedWings) async {
    return showDialog<Wing>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Primary Wing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose which wing to keep. The other wings will be merged into this one:'),
            const SizedBox(height: 16),
            ...selectedWings.map((wing) => ListTile(
              title: Text(wing.displayName),
              subtitle: Text('${widget.flightCounts[wing.id!] ?? 0} flights'),
              onTap: () => Navigator.of(context).pop(wing),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showMergeConfirmation(List<Wing> selectedWings, Wing primaryWing) async {
    final totalFlights = selectedWings
        .where((w) => w.id != primaryWing.id)
        .fold(0, (sum, w) => sum + (widget.flightCounts[w.id!] ?? 0));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Wing Merge'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Primary wing: ${primaryWing.displayName}'),
            const SizedBox(height: 8),
            const Text('Wings to merge:'),
            ...selectedWings
                .where((w) => w.id != primaryWing.id)
                .map((w) => Text('  • ${w.displayName} (${widget.flightCounts[w.id!] ?? 0} flights)')),
            const SizedBox(height: 16),
            Text('This will reassign $totalFlights flights to the primary wing.'),
            const SizedBox(height: 8),
            const Text('The merged wings will be deleted after reassigning their flights.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _performMerge(List<Wing> selectedWings, Wing primaryWing) async {
    setState(() => _isProcessing = true);

    try {
      final wingIdsToMerge = selectedWings
          .where((w) => w.id != primaryWing.id)
          .map((w) => w.id!)
          .toList();

      await _databaseService.mergeWings(primaryWing.id!, wingIdsToMerge);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully merged ${wingIdsToMerge.length} wings into ${primaryWing.displayName}'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Return success
      }
    } catch (e) {
      LoggingService.error('WingMergeDialog: Failed to merge wings', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error merging wings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Merge Wings'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            Text(
              'Select 2 or more wings to merge. All flights will be reassigned to the primary wing.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _selectedWingIds.isNotEmpty
                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _selectedWingIds.isNotEmpty
                    ? '${_selectedWingIds.length} wing${_selectedWingIds.length == 1 ? '' : 's'} selected'
                    : 'Select 2 or more wings below',
                style: TextStyle(
                  color: _selectedWingIds.isNotEmpty
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: _selectedWingIds.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: widget.wings.length,
                itemBuilder: (context, index) {
                  final wing = widget.wings[index];
                  final isSelected = _selectedWingIds.contains(wing.id);
                  final flightCount = widget.flightCounts[wing.id!] ?? 0;

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: wing.id != null
                        ? (value) => _toggleWingSelection(wing.id!)
                        : null,
                    title: Text(wing.displayName),
                    subtitle: Text('$flightCount flight${flightCount == 1 ? '' : 's'}'),
                    secondary: CircleAvatar(
                      backgroundColor: wing.active
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[400],
                      radius: 16,
                      child: const Icon(
                        Icons.paragliding,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isProcessing || _selectedWingIds.length < 2
              ? null
              : _proceedToMerge,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Merge'),
        ),
      ],
    );
  }
}