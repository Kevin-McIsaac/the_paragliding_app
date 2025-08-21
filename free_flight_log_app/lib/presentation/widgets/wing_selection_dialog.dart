import 'package:flutter/material.dart';
import '../../data/models/wing.dart';

/// Result wrapper for wing selection
class WingSelectionResult {
  final Wing? selectedWing;
  
  const WingSelectionResult(this.selectedWing);
}

/// Custom wing selection dialog with search functionality
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
  late List<Wing> _filteredWings;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Wing? _selectedWing;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredWings = widget.wings;
    _selectedWing = widget.currentWing;
    
    // Sort wings by manufacturer and model for easier browsing
    _filteredWings.sort((a, b) {
      final aManufacturer = a.manufacturer ?? '';
      final bManufacturer = b.manufacturer ?? '';
      final manufacturerCompare = aManufacturer.compareTo(bManufacturer);
      if (manufacturerCompare != 0) return manufacturerCompare;
      
      final aModel = a.model ?? '';
      final bModel = b.model ?? '';
      return aModel.compareTo(bModel);
    });
    
    // Scroll to selected item after the widget is built
    if (_selectedWing != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelectedWing();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  void _scrollToSelectedWing() {
    if (_selectedWing == null || !_scrollController.hasClients) return;
    
    // Find the index of the selected wing
    final index = _filteredWings.indexOf(_selectedWing!);
    if (index == -1) return;
    
    // Account for "No wing" option (56px) and divider (1px)
    // Estimate item height: ListTile with dense:true is approximately 56 pixels
    // For wings with subtitle (size), it's slightly taller, around 72 pixels
    final hasSubtitle = _selectedWing!.size != null && _selectedWing!.size!.isNotEmpty;
    final itemHeight = hasSubtitle ? 72.0 : 56.0;
    
    // Calculate scroll position
    double scrollPosition = 57 + (index * itemHeight);
    
    // Ensure we don't scroll beyond the maximum extent
    if (_scrollController.position.maxScrollExtent > 0) {
      scrollPosition = scrollPosition.clamp(0, _scrollController.position.maxScrollExtent);
    }
    
    // Animate to the position
    _scrollController.animateTo(
      scrollPosition,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _filterWings(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredWings = List.from(widget.wings)
          ..sort((a, b) {
            final aManufacturer = a.manufacturer ?? '';
            final bManufacturer = b.manufacturer ?? '';
            final manufacturerCompare = aManufacturer.compareTo(bManufacturer);
            if (manufacturerCompare != 0) return manufacturerCompare;
            
            final aModel = a.model ?? '';
            final bModel = b.model ?? '';
            return aModel.compareTo(bModel);
          });
      } else {
        _filteredWings = widget.wings
            .where((wing) => 
                (wing.manufacturer?.toLowerCase().contains(_searchQuery) ?? false) ||
                (wing.model?.toLowerCase().contains(_searchQuery) ?? false))
            .toList()
          ..sort((a, b) {
            final aManufacturer = a.manufacturer ?? '';
            final bManufacturer = b.manufacturer ?? '';
            final manufacturerCompare = aManufacturer.compareTo(bManufacturer);
            if (manufacturerCompare != 0) return manufacturerCompare;
            
            final aModel = a.model ?? '';
            final bModel = b.model ?? '';
            return aModel.compareTo(bModel);
          });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select Wing'),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search manufacturer or model...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterWings('');
                      },
                    )
                  : null,
            ),
            onChanged: _filterWings,
            autofocus: true,
          ),
          if (_filteredWings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_filteredWings.length} wing${_filteredWings.length != 1 ? 's' : ''} found',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // No wing option
            ListTile(
              title: const Text('No wing'),
              leading: Radio<Wing?>(
                value: null,
                groupValue: _selectedWing,
                onChanged: (Wing? value) {
                  setState(() {
                    _selectedWing = value;
                  });
                },
              ),
              onTap: () {
                setState(() {
                  _selectedWing = null;
                });
              },
              dense: true,
            ),
            const Divider(),
            // Wing list
            Expanded(
              child: _filteredWings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, 
                               size: 48, 
                               color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No wings match your search',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _filteredWings.length,
                      itemBuilder: (context, index) {
                        final wing = _filteredWings[index];
                        return RadioListTile<Wing?>(
                          title: Text('${wing.manufacturer ?? 'Unknown'} ${wing.model ?? 'Unknown'}'),
                          subtitle: wing.size != null
                              ? Text('Size: ${wing.size}')
                              : null,
                          value: wing,
                          groupValue: _selectedWing,
                          onChanged: (Wing? value) {
                            setState(() {
                              _selectedWing = value;
                            });
                          },
                          dense: true,
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
          onPressed: () => Navigator.of(context).pop(WingSelectionResult(_selectedWing)),
          child: const Text('Select'),
        ),
      ],
    );
  }
}