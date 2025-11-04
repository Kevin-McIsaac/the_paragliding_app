import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/paragliding_site.dart';
import '../../data/models/wind_data.dart';
import '../../data/models/weather_model.dart';
import '../../utils/flyability_constants.dart';
import 'flyability_cell.dart';

/// Widget for displaying hourly flyability forecast from multiple weather models
///
/// Shows a Model × Hours table with:
/// - N rows (one for each weather model)
/// - 13 columns (hours from 7am to 7pm)
/// - Color-coded flyability cells using FlyabilityCellWidget
///
/// The currently selected model from preferences is highlighted
class MultiModelForecastTable extends StatelessWidget {
  final ParaglidingSite site;
  final DateTime date;
  final Map<WeatherModel, List<WindData?>> windDataByModel; // model -> hourly data (7am-7pm)
  final double maxWindSpeed;
  final double cautionWindSpeed;
  final WeatherModel? selectedModel; // Currently selected model to highlight
  final double? modelColumnWidth;

  const MultiModelForecastTable({
    super.key,
    required this.site,
    required this.date,
    required this.windDataByModel,
    required this.maxWindSpeed,
    required this.cautionWindSpeed,
    this.selectedModel,
    this.modelColumnWidth = 140.0,
  });

  @override
  Widget build(BuildContext context) {
    // Get all models and sort them: selected model first, then alphabetically
    final models = windDataByModel.keys.toList();
    models.sort((a, b) {
      if (a == selectedModel) return -1;
      if (b == selectedModel) return 1;
      return a.displayName.compareTo(b.displayName);
    });

    return Table(
      defaultColumnWidth: const FixedColumnWidth(FlyabilityConstants.cellSize),
      columnWidths: {
        0: FixedColumnWidth(modelColumnWidth!),
      },
      border: TableBorder.all(
        color: Theme.of(context).dividerColor,
        width: 1.0,
      ),
      children: [
        _buildHeaderRow(context),
        ...models.map((model) => _buildModelRow(context, model)),
      ],
    );
  }

  TableRow _buildHeaderRow(BuildContext context) {
    return TableRow(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      children: [
        _buildHeaderCell(context, _formatDate(date), isFirst: true),
        ...List.generate(
          FlyabilityConstants.hoursToShow,
          (hour) => _buildHeaderCell(context, '${hour + FlyabilityConstants.startHour}h'),
        ),
      ],
    );
  }

  Widget _buildHeaderCell(BuildContext context, String text, {bool isFirst = false}) {
    return Container(
      height: FlyabilityConstants.cellSize,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isFirst ? FontWeight.bold : FontWeight.w500,
          fontSize: isFirst ? 12 : 10,
        ),
      ),
    );
  }

  TableRow _buildModelRow(BuildContext context, WeatherModel model) {
    final modelWindData = windDataByModel[model];
    final isSelected = model == selectedModel;

    return TableRow(
      decoration: isSelected
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
            )
          : null,
      children: [
        // Model name cell
        Container(
          height: FlyabilityConstants.cellSize,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          decoration: isSelected
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  ),
                )
              : null,
          child: Tooltip(
            message: model.description,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    model.displayName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Theme.of(context).colorScheme.primary : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
        // Hour cells (7am-7pm)
        ...List.generate(FlyabilityConstants.hoursToShow, (hourIndex) {
          if (modelWindData == null || hourIndex >= modelWindData.length || modelWindData[hourIndex] == null) {
            return _buildEmptyCell();
          }

          final windData = modelWindData[hourIndex]!;
          return FlyabilityCellWidget(
            windData: windData,
            site: site,
            maxWindSpeed: maxWindSpeed,
            cautionWindSpeed: cautionWindSpeed,
          );
        }),
      ],
    );
  }

  Widget _buildEmptyCell() {
    return Container(
      height: FlyabilityConstants.cellSize,
      alignment: Alignment.center,
      child: const Text('-', style: TextStyle(fontSize: 10, color: Colors.grey)),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) return 'Today';
    if (checkDate == today.add(const Duration(days: 1))) return 'Tomorrow';

    // Format as "Mon 23" or "Tue 24"
    return DateFormat('EEE d').format(date);
  }
}
