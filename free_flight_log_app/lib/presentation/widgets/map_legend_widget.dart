import 'package:flutter/material.dart';
import '../../data/models/airspace_enums.dart';
import '../../services/airspace_geojson_service.dart';

/// Widget for displaying map legend
class MapLegendWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final airspaceService = AirspaceGeoJsonService.instance;
    final visibleIcaoClassesList = excludedIcaoClasses.entries
        .where((entry) => entry.value == false)  // false = not excluded = visible
        .map((entry) => entry.key)
        .toList();

    return Container(
        decoration: const BoxDecoration(
          color: Color(0xCC000000), // 80% black for better readability
          borderRadius: BorderRadius.all(Radius.circular(8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Legend',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),

              // Sites section
              if (sitesEnabled) ...[
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
                if (sitesEnabled) ...[
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
                  final style = airspaceService.getStyleForIcaoClass(icaoClass);
                  if (style != null) {
                    return Column(
                      children: [
                        Tooltip(
                          message: icaoClass.tooltip,
                          preferBelow: false,
                          decoration: BoxDecoration(
                            color: const Color(0xE6000000),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          textStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                          child: _buildLegendItem(
                            null,
                            style.borderColor,
                            'Class ${icaoClass.abbreviation}',
                            isSquare: true,
                          ),
                        ),
                        if (index < visibleIcaoClassesList.length - 1)
                          const SizedBox(height: 2),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                }).toList(),
              ],

              if (isMergeMode) ...[
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