import 'package:flutter/material.dart';
import '../../data/models/wing.dart';
import '../../services/logging_service.dart';

class EditWingDialog extends StatefulWidget {
  final Wing wing;

  const EditWingDialog({super.key, required this.wing});

  @override
  State<EditWingDialog> createState() => _EditWingDialogState();
}

class _EditWingDialogState extends State<EditWingDialog> {
  late TextEditingController _manufacturerController;
  late TextEditingController _modelController;
  late TextEditingController _sizeController;
  late TextEditingController _colorController;
  late TextEditingController _notesController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _manufacturerController = TextEditingController(text: widget.wing.manufacturer ?? '');
    _modelController = TextEditingController(text: widget.wing.model ?? '');
    _sizeController = TextEditingController(text: widget.wing.size ?? '');
    _colorController = TextEditingController(text: widget.wing.color ?? '');
    _notesController = TextEditingController(text: widget.wing.notes ?? '');
  }

  @override
  void dispose() {
    _manufacturerController.dispose();
    _modelController.dispose();
    _sizeController.dispose();
    _colorController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _getDisplayName() {
    List<String> parts = [];
    final manufacturer = _manufacturerController.text.trim();
    final model = _modelController.text.trim();
    
    if (manufacturer.isNotEmpty) {
      parts.add(manufacturer);
    }
    if (model.isNotEmpty) {
      parts.add(model);
    }
    
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
    
    // Fallback to original name if no manufacturer/model
    return widget.wing.name;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with title and close button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Edit Wing',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              // Form content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Preview of display name
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.paragliding,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _getDisplayName(),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Manufacturer field
                      TextFormField(
                        controller: _manufacturerController,
                        decoration: const InputDecoration(
                          labelText: 'Manufacturer',
                          hintText: 'e.g., Ozone, Advance, Nova',
                          prefixIcon: Icon(Icons.business),
                        ),
                        textCapitalization: TextCapitalization.words,
                        onChanged: (value) {
                          setState(() {
                            // Update display name preview
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      // Model field
                      TextFormField(
                        controller: _modelController,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          hintText: 'e.g., Rush, Epsilon, Mentor',
                          prefixIcon: Icon(Icons.flight),
                        ),
                        textCapitalization: TextCapitalization.words,
                        onChanged: (value) {
                          setState(() {
                            // Update display name preview
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      // Size field
                      TextFormField(
                        controller: _sizeController,
                        decoration: const InputDecoration(
                          labelText: 'Size',
                          hintText: 'e.g., S, M, L, 23, 25, 27',
                          prefixIcon: Icon(Icons.straighten),
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 16),
                      // Color field
                      TextFormField(
                        controller: _colorController,
                        decoration: const InputDecoration(
                          labelText: 'Color',
                          hintText: 'e.g., Red, Blue, Yellow',
                          prefixIcon: Icon(Icons.palette),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 16),
                      // Notes field
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Additional information about the wing',
                          prefixIcon: Icon(Icons.notes),
                        ),
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ],
                  ),
                ),
              ),
              // Action buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saveWing,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveWing() {
    if (_formKey.currentState!.validate()) {
      try {
        // Create updated wing with new values
        final updatedWing = Wing(
          id: widget.wing.id,
          name: _getDisplayName(), // Update name based on manufacturer/model
          manufacturer: _manufacturerController.text.trim().isEmpty 
              ? null 
              : _manufacturerController.text.trim(),
          model: _modelController.text.trim().isEmpty 
              ? null 
              : _modelController.text.trim(),
          size: _sizeController.text.trim().isEmpty 
              ? null 
              : _sizeController.text.trim(),
          color: _colorController.text.trim().isEmpty 
              ? null 
              : _colorController.text.trim(),
          notes: _notesController.text.trim().isEmpty 
              ? null 
              : _notesController.text.trim(),
          purchaseDate: widget.wing.purchaseDate,
          active: widget.wing.active,
          createdAt: widget.wing.createdAt,
        );
        
        LoggingService.info('EditWingDialog: Wing updated - ${updatedWing.name}');
        Navigator.of(context).pop(updatedWing);
      } catch (e) {
        LoggingService.error('EditWingDialog: Error updating wing', e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating wing: $e')),
        );
      }
    }
  }
}