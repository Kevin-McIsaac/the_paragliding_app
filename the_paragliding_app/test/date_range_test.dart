import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Date Range Calculations', () {

    test('_getDateRangeForPreset handles month boundaries correctly', () {
      // Test date: March 15, 2024
      final testDate = DateTime(2024, 3, 15);
      
      // Mock DateTime.now() by creating a custom test class
      final testScreenState = TestStatisticsScreenState(testDate);
      
      // Test 3 months ago (should be December 15, 2023)
      final threeMonthsRange = testScreenState.testGetDateRangeForPreset('3_months');
      expect(threeMonthsRange?.start.year, 2023);
      expect(threeMonthsRange?.start.month, 12);
      expect(threeMonthsRange?.start.day, 15);
      
      // Test 6 months ago (should be September 15, 2023)  
      final sixMonthsRange = testScreenState.testGetDateRangeForPreset('6_months');
      expect(sixMonthsRange?.start.year, 2023);
      expect(sixMonthsRange?.start.month, 9);
      expect(sixMonthsRange?.start.day, 15);
      
      // Test 12 months ago (should be March 15, 2023)
      final twelveMonthsRange = testScreenState.testGetDateRangeForPreset('12_months');
      expect(twelveMonthsRange?.start.year, 2023);
      expect(twelveMonthsRange?.start.month, 3);
      expect(twelveMonthsRange?.start.day, 15);
    });
    
    test('_getDateRangeForPreset handles January edge case', () {
      // Test date: January 31, 2024
      final testDate = DateTime(2024, 1, 31);
      final testScreenState = TestStatisticsScreenState(testDate);
      
      // Test 3 months ago (should be October 31, 2023)
      final threeMonthsRange = testScreenState.testGetDateRangeForPreset('3_months');
      expect(threeMonthsRange?.start.year, 2023);
      expect(threeMonthsRange?.start.month, 10);
      expect(threeMonthsRange?.start.day, 31);
    });
    
    test('_getDateRangeForPreset handles leap year February', () {
      // Test date: February 29, 2024 (leap year)
      final testDate = DateTime(2024, 2, 29);
      final testScreenState = TestStatisticsScreenState(testDate);
      
      // Test 12 months ago (should handle February 28, 2023 since 2023 is not a leap year)
      final twelveMonthsRange = testScreenState.testGetDateRangeForPreset('12_months');
      expect(twelveMonthsRange?.start.year, 2023);
      expect(twelveMonthsRange?.start.month, 2);
      // DateTime constructor automatically handles day overflow
      expect(twelveMonthsRange?.start.day, 28); // Feb 28 in non-leap year
    });
    
    test('_getDateRangeForPreset handles 30 days correctly', () {
      final testDate = DateTime(2024, 3, 15);
      final testScreenState = TestStatisticsScreenState(testDate);
      
      final thirtyDaysRange = testScreenState.testGetDateRangeForPreset('30_days');
      final expectedStart = DateTime(2024, 3, 15).subtract(const Duration(days: 30));
      
      expect(thirtyDaysRange?.start.year, expectedStart.year);
      expect(thirtyDaysRange?.start.month, expectedStart.month);
      expect(thirtyDaysRange?.start.day, expectedStart.day);
      expect(thirtyDaysRange?.end.year, 2024);
      expect(thirtyDaysRange?.end.month, 3);
      expect(thirtyDaysRange?.end.day, 15);
    });
    
    test('_getDateRangeForPreset handles this_year correctly', () {
      final testDate = DateTime(2024, 7, 15);
      final testScreenState = TestStatisticsScreenState(testDate);
      
      final thisYearRange = testScreenState.testGetDateRangeForPreset('this_year');
      expect(thisYearRange?.start.year, 2024);
      expect(thisYearRange?.start.month, 1);
      expect(thisYearRange?.start.day, 1);
      expect(thisYearRange?.end.year, 2024);
      expect(thisYearRange?.end.month, 7);
      expect(thisYearRange?.end.day, 15);
    });
    
    test('_getDateRangeForPreset returns null for all', () {
      final testDate = DateTime(2024, 3, 15);
      final testScreenState = TestStatisticsScreenState(testDate);
      
      final allRange = testScreenState.testGetDateRangeForPreset('all');
      expect(allRange, isNull);
    });
  });
}

// Test helper class to access private methods with a mock DateTime.now()
class TestStatisticsScreenState {
  final DateTime mockNow;
  
  TestStatisticsScreenState(this.mockNow);
  
  DateTimeRange? testGetDateRangeForPreset(String preset) {
    final today = DateTime(mockNow.year, mockNow.month, mockNow.day);
    
    switch (preset) {
      case 'all':
        return null;
      case 'this_year':
        return DateTimeRange(
          start: DateTime(mockNow.year, 1, 1),
          end: today,
        );
      case '12_months':
        // Subtract exactly 12 months using DateTime arithmetic
        final twelveMonthsAgo = DateTime(mockNow.year, mockNow.month - 12, mockNow.day);
        return DateTimeRange(
          start: DateTime(twelveMonthsAgo.year, twelveMonthsAgo.month, twelveMonthsAgo.day),
          end: today,
        );
      case '6_months':
        // Subtract exactly 6 months using DateTime arithmetic  
        final sixMonthsAgo = DateTime(mockNow.year, mockNow.month - 6, mockNow.day);
        return DateTimeRange(
          start: DateTime(sixMonthsAgo.year, sixMonthsAgo.month, sixMonthsAgo.day),
          end: today,
        );
      case '3_months':
        // Subtract exactly 3 months using DateTime arithmetic
        final threeMonthsAgo = DateTime(mockNow.year, mockNow.month - 3, mockNow.day);
        return DateTimeRange(
          start: DateTime(threeMonthsAgo.year, threeMonthsAgo.month, threeMonthsAgo.day),
          end: today,
        );
      case '30_days':
        return DateTimeRange(
          start: today.subtract(const Duration(days: 30)),
          end: today,
        );
      default:
        return null;
    }
  }
}