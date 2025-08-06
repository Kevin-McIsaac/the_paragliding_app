import 'package:flutter/material.dart';

/// Utility class for common UI operations and consistent user feedback
class UiUtils {
  /// Shows a success message with a green snackbar
  /// 
  /// Example: UiUtils.showSuccessMessage(context, 'Flight saved successfully');
  static void showSuccessMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Shows an error message with a red snackbar
  /// 
  /// Example: UiUtils.showErrorMessage(context, 'Failed to save flight');
  static void showErrorMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4), // Longer for errors
      ),
    );
  }

  /// Shows a warning message with an orange snackbar
  /// 
  /// Example: UiUtils.showWarningMessage(context, 'Some data may be incomplete');
  static void showWarningMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Shows an info message with the default snackbar color
  /// 
  /// Example: UiUtils.showInfoMessage(context, 'Loading data...');
  static void showInfoMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Shows a generic error message for exceptions
  /// 
  /// Automatically formats the error with a standard message
  /// Example: UiUtils.showExceptionError(context, 'save flight', e);
  static void showExceptionError(BuildContext context, String operation, dynamic error) {
    final message = 'Error ${operation}: ${error.toString()}';
    showErrorMessage(context, message);
  }

  /// Shows a confirmation dialog with customizable title, message, and button text
  /// 
  /// Returns true if user confirms, false if cancelled
  /// Example: 
  /// final confirmed = await UiUtils.showConfirmationDialog(
  ///   context, 
  ///   'Delete Flight', 
  ///   'Are you sure you want to delete this flight?'
  /// );
  static Future<bool> showConfirmationDialog(
    BuildContext context,
    String title,
    String message, {
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    Color? confirmColor,
  }) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: confirmColor != null 
              ? FilledButton.styleFrom(backgroundColor: confirmColor)
              : null,
            child: Text(confirmText),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Shows a delete confirmation dialog with red styling
  /// 
  /// Returns true if user confirms deletion
  /// Example:
  /// final confirmed = await UiUtils.showDeleteConfirmation(
  ///   context, 
  ///   'Delete Site', 
  ///   'Are you sure you want to delete "Site Name"?'
  /// );
  static Future<bool> showDeleteConfirmation(
    BuildContext context,
    String title,
    String message,
  ) async {
    return showConfirmationDialog(
      context,
      title,
      message,
      confirmText: 'Delete',
      confirmColor: Colors.red,
    );
  }

  /// Shows a simple error dialog with an OK button
  /// 
  /// Use this for more detailed error messages that need dialog presentation
  /// Example: UiUtils.showErrorDialog(context, 'Connection Error', 'Unable to connect to server');
  static void showErrorDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Shows a loading dialog that blocks user interaction
  /// 
  /// Returns a function that can be called to dismiss the dialog
  /// Example:
  /// final dismissLoading = UiUtils.showLoadingDialog(context, 'Saving flight...');
  /// // Do async work
  /// dismissLoading();
  static VoidCallback showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );

    return () {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    };
  }
}