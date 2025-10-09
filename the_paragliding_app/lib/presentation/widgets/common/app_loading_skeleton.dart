import 'package:flutter/material.dart';

/// A reusable skeleton loading widget with shimmer animation.
/// 
/// Used across screens to provide consistent loading states while data is being fetched.
/// Supports different skeleton types like stat cards, list items, and custom shapes.
class AppLoadingSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final EdgeInsets? margin;
  final Color? baseColor;
  final Color? highlightColor;

  const AppLoadingSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 6.0,
    this.margin,
    this.baseColor,
    this.highlightColor,
  });

  /// Factory for creating a stat card skeleton
  factory AppLoadingSkeleton.statCard({
    double width = 80,
    double height = 60,
    EdgeInsets? margin,
  }) {
    return AppLoadingSkeleton(
      width: width,
      height: height,
      borderRadius: 8,
      margin: margin,
    );
  }

  /// Factory for creating a list item skeleton
  factory AppLoadingSkeleton.listItem({
    double height = 72,
    EdgeInsets? margin,
  }) {
    return AppLoadingSkeleton(
      width: double.infinity,
      height: height,
      borderRadius: 8,
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  /// Factory for creating a text line skeleton
  factory AppLoadingSkeleton.text({
    double width = 120,
    double height = 16,
    EdgeInsets? margin,
  }) {
    return AppLoadingSkeleton(
      width: width,
      height: height,
      borderRadius: 4,
      margin: margin,
    );
  }

  /// Factory for creating a circular skeleton (for avatars)
  factory AppLoadingSkeleton.circle({
    double diameter = 40,
    EdgeInsets? margin,
  }) {
    return AppLoadingSkeleton(
      width: diameter,
      height: diameter,
      borderRadius: diameter / 2,
      margin: margin,
    );
  }

  @override
  State<AppLoadingSkeleton> createState() => _AppLoadingSkeletonState();
}

class _AppLoadingSkeletonState extends State<AppLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _animation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutSine,
    ));
    
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.baseColor ?? Colors.grey[300]!;
    final highlightColor = widget.highlightColor ?? Colors.grey[100]!;

    return Container(
      margin: widget.margin,
      width: widget.width == double.infinity ? null : widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              gradient: LinearGradient(
                colors: [
                  baseColor,
                  highlightColor,
                  baseColor,
                ],
                stops: const [0.0, 0.5, 1.0],
                begin: Alignment(_animation.value - 1, 0),
                end: Alignment(_animation.value, 0),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A skeleton for stat cards used in flight lists
class AppStatCardSkeleton extends StatelessWidget {
  final EdgeInsets? padding;

  const AppStatCardSkeleton({
    super.key,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: Column(
        children: [
          AppLoadingSkeleton.text(width: 60, height: 12),
          const SizedBox(height: 8),
          AppLoadingSkeleton.text(width: 40, height: 20),
        ],
      ),
    );
  }
}

/// A skeleton for list rows (like flight entries)
class AppListRowSkeleton extends StatelessWidget {
  final EdgeInsets? padding;

  const AppListRowSkeleton({
    super.key,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: AppLoadingSkeleton.text(height: 16),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: AppLoadingSkeleton.text(height: 16),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: AppLoadingSkeleton.text(height: 16),
          ),
          const SizedBox(width: 16),
          AppLoadingSkeleton.text(width: 40, height: 16),
        ],
      ),
    );
  }
}

/// A skeleton for wing cards
class AppWingCardSkeleton extends StatelessWidget {
  const AppWingCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AppLoadingSkeleton.circle(diameter: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppLoadingSkeleton.text(width: 120, height: 16),
                  const SizedBox(height: 8),
                  AppLoadingSkeleton.text(width: 80, height: 12),
                ],
              ),
            ),
            AppLoadingSkeleton.text(width: 60, height: 16),
          ],
        ),
      ),
    );
  }
}

/// A compound skeleton that displays multiple loading elements
class AppPageLoadingSkeleton extends StatelessWidget {
  final bool showStats;
  final int listItemCount;
  final Widget? customHeader;

  const AppPageLoadingSkeleton({
    super.key,
    this.showStats = true,
    this.listItemCount = 8,
    this.customHeader,
  });

  /// Factory for flight list page skeleton
  factory AppPageLoadingSkeleton.flightList() {
    return const AppPageLoadingSkeleton(
      showStats: true,
      listItemCount: 10,
    );
  }

  /// Factory for wing management page skeleton
  factory AppPageLoadingSkeleton.wingManagement() {
    return const AppPageLoadingSkeleton(
      showStats: false,
      listItemCount: 6,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Stats skeleton
        if (showStats)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: Theme.of(context).colorScheme.surface,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                AppStatCardSkeleton(),
                AppStatCardSkeleton(),
              ],
            ),
          ),
        
        // Custom header if provided
        if (customHeader != null) customHeader!,
        
        // List skeleton
        Expanded(
          child: ListView.builder(
            itemCount: listItemCount,
            itemBuilder: (context, index) => const AppListRowSkeleton(),
          ),
        ),
      ],
    );
  }
}

/// A skeleton for expansion cards
class AppExpansionCardSkeleton extends StatelessWidget {
  const AppExpansionCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppLoadingSkeleton.circle(diameter: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppLoadingSkeleton.text(width: 120, height: 16),
                      const SizedBox(height: 4),
                      AppLoadingSkeleton.text(width: 200, height: 14),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppLoadingSkeleton.text(width: double.infinity, height: 12),
            const SizedBox(height: 8),
            AppLoadingSkeleton.text(width: 180, height: 12),
            const SizedBox(height: 8),
            AppLoadingSkeleton.text(width: 220, height: 12),
          ],
        ),
      ),
    );
  }
}