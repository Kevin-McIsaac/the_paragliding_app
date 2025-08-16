import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/wing.dart';
import '../../services/database_service.dart';

class EditWingScreen extends StatefulWidget {
  final Wing? wing;

  const EditWingScreen({super.key, this.wing});

  @override
  State<EditWingScreen> createState() => _EditWingScreenState();
}

class _EditWingScreenState extends State<EditWingScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _databaseService = DatabaseService.instance;

  late TextEditingController _nameController;
  late TextEditingController _manufacturerController;
  late TextEditingController _modelController;
  late TextEditingController _sizeController;
  late TextEditingController _colorController;
  late TextEditingController _notesController;

  DateTime? _purchaseDate;
  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _nameController = TextEditingController(text: widget.wing?.name ?? '');
    _manufacturerController = TextEditingController(text: widget.wing?.manufacturer ?? '');
    _modelController = TextEditingController(text: widget.wing?.model ?? '');
    _sizeController = TextEditingController(text: widget.wing?.size ?? '');
    _colorController = TextEditingController(text: widget.wing?.color ?? '');
    _notesController = TextEditingController(text: widget.wing?.notes ?? '');
    _purchaseDate = widget.wing?.purchaseDate;
    _isActive = widget.wing?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _manufacturerController.dispose();
    _modelController.dispose();
    _sizeController.dispose();
    _colorController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectPurchaseDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _purchaseDate) {
      setState(() {
        _purchaseDate = picked;
      });
    }
  }

  Future<void> _saveWing() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final wing = Wing(
        id: widget.wing?.id,
        name: _nameController.text.trim(),
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
        purchaseDate: _purchaseDate,
        active: _isActive,
        notes: _notesController.text.trim().isEmpty 
          ? null 
          : _notesController.text.trim(),
        createdAt: widget.wing?.createdAt,
      );

      if (widget.wing == null) {
        // Creating new wing
        await _databaseService.insertWing(wing);
      } else {
        // Updating existing wing
        await _databaseService.updateWing(wing);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving wing: $e')),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, y').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.wing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Wing' : 'Add Wing'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveWing,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Basic Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Basic Information',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Wing Name *',
                          prefixIcon: Icon(Icons.paragliding),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Wing name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _manufacturerController,
                              decoration: const InputDecoration(
                                labelText: 'Manufacturer',
                                prefixIcon: Icon(Icons.business),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _modelController,
                              decoration: const InputDecoration(
                                labelText: 'Model',
                                prefixIcon: Icon(Icons.model_training),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _sizeController,
                              decoration: const InputDecoration(
                                labelText: 'Size',
                                prefixIcon: Icon(Icons.straighten),
                                border: OutlineInputBorder(),
                                hintText: 'e.g., XS, S, M, L, XL',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _colorController,
                              decoration: const InputDecoration(
                                labelText: 'Color',
                                prefixIcon: Icon(Icons.palette),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Purchase Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Purchase Information',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.calendar_today),
                        title: const Text('Purchase Date'),
                        subtitle: Text(
                          _purchaseDate != null 
                            ? _formatDate(_purchaseDate!)
                            : 'Not set',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_purchaseDate != null)
                              IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _purchaseDate = null;
                                  });
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: _selectPurchaseDate,
                            ),
                          ],
                        ),
                        onTap: _selectPurchaseDate,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Status and Notes
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status & Notes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Active'),
                        subtitle: Text(
                          _isActive 
                            ? 'Wing is available for flight logging'
                            : 'Wing is hidden from flight logging',
                        ),
                        value: _isActive,
                        onChanged: (value) {
                          setState(() {
                            _isActive = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          prefixIcon: Icon(Icons.note),
                          border: OutlineInputBorder(),
                          hintText: 'Any additional notes about this wing...',
                        ),
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}