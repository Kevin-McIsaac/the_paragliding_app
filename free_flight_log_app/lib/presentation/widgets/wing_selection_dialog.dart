import 'package:flutter/material.dart';
import '../../data/models/wing.dart';

class WingSelectionDialog extends StatefulWidget {
  final List<Wing> wings;
  final Wing? currentWing;

  const WingSelectionDialog({
    super.key,
    required this.wings,
    required this.currentWing,
  });

  @override
  State<WingSelectionDialog> createState() => _WingSelectionDialogState();
}

class _WingSelectionDialogState extends State<WingSelectionDialog> {
  Wing? _selectedWing;

  @override
  void initState() {
    super.initState();
    _selectedWing = widget.currentWing;
  }

  @override
  Widget build(BuildContext context) {
    final sortedWings = List<Wing>.from(widget.wings)
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return AlertDialog(
      title: const Text('Select Wing'),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: Column(
          children: [
            ListTile(
              title: const Text('No wing'),
              leading: Radio<Wing?>(
                value: null,
                groupValue: _selectedWing,
                onChanged: (value) => setState(() => _selectedWing = value),
              ),
              onTap: () => setState(() => _selectedWing = null),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: sortedWings.length,
                itemBuilder: (context, index) {
                  final wing = sortedWings[index];
                  return ListTile(
                    title: Text(wing.displayName),
                    subtitle: wing.size?.isNotEmpty == true ? Text('Size: ${wing.size}') : null,
                    leading: Radio<Wing>(
                      value: wing,
                      groupValue: _selectedWing,
                      onChanged: (value) => setState(() => _selectedWing = value),
                    ),
                    onTap: () => setState(() => _selectedWing = wing),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedWing),
          child: const Text('Select'),
        ),
      ],
    );
  }
}