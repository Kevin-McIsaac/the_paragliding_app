import 'package:flutter/material.dart';
import '../../data/models/airspace_enums.dart';

/// Widget for displaying map legend
class MapLegendWidget extends StatefulWidget {
  final bool isMergeMode;
  final bool sitesEnabled;
  final Map<IcaoClass, bool> excludedIcaoClasses;

  const MapLegendWidget({
    super.key,
    this.isMergeMode = false,
    this.sitesEnabled = true,
    this.excludedIcaoClasses = const {},
  });

  @override
  State<MapLegendWidget> createState() => _MapLegendWidgetState();
}

class _MapLegendWidgetState extends State<MapLegendWidget> with SingleTickerProviderStateMixin {
  bool _isExpanded = true;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    if (_isExpanded) {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleIcaoClassesList = widget.excludedIcaoClasses.entries
        .where((entry) => entry.value == false)  // false = not excluded = visible
        .map((entry) => entry.key)
        .toList();

    return Container(
        decoration: BoxDecoration(
          color: const Color(0x80000000), // 50% black to match other controls
          borderRadius: const BorderRadius.all(Radius.circular(4)), // Match search bar radius
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 4, // Match other controls
              offset: const Offset(0, 2), // Match other controls
            ),
          ],
        ),
        child: Padding(
          // Conditional padding: less when collapsed to match search bar height
          padding: _isExpanded
              ? const EdgeInsets.all(12.0)
              : const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clickable header with expand/collapse
              InkWell(
                onTap: _toggleExpanded,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Legend',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.white70,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),

              // Animated expandable content
              SizeTransition(
                sizeFactor: _expandAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),

                    // Sites section
                    if (widget.sitesEnabled) ...[
                _buildSectionHeader('Sites'),
                _buildLegendItem(
                  Icons.location_on,
                  Colors.blue,
                  'Local sites (DB)',
                ),
                const SizedBox(height: 2),
                _buildLegendItem(
                  Icons.location_on,
                  Colors.green,
                  'API sites',
                ),
              ],

                    // ICAO Classes section
                    if (visibleIcaoClassesList.isNotEmpty) ...[
                      if (widget.sitesEnabled) ...[
                  const SizedBox(height: 8),
                  Container(
                    height: 1,
                    color: Colors.white12,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ],
                _buildSectionHeader('Airspace Classes'),
                ...visibleIcaoClassesList.asMap().entries.map((entry) {
                  final index = entry.key;
                  final icaoClass = entry.value;
                  return Column(
                    children: [
                      Tooltip(
                        message: icaoClass.description,
                        child: _buildLegendItem(
                          null,
                          icaoClass.borderColor,
                          'Class ${icaoClass.abbreviation}',
                          isSquare: true,
                        ),
                      ),
                      if (index < visibleIcaoClassesList.length - 1)
                        const SizedBox(height: 2),
                    ],
                  );
                }).toList(),
              ],

                    if (widget.isMergeMode) ...[
                Container(
                  height: 1,
                  color: Colors.white12,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                ),
                      const Text(
                        'Merge Mode Active',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Drop site on target',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0, top: 2.0),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          color: Colors.white60,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildLegendItem(IconData? icon, Color color, String label, {bool isCircle = false, bool isSquare = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, color: color, size: 14)
          else if (isCircle)
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            )
          else if (isSquare)
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.3), // Semi-transparent fill like airspace
                border: Border.all(color: color, width: 1.5),
                shape: BoxShape.rectangle,
              ),
            )
          else
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.rectangle,
              ),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}