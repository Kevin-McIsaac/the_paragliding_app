import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/cesium_token_validator.dart';
import '../../services/logging_service.dart';
import '../../utils/preferences_helper.dart';

/// Widget for managing user's Cesium Ion access token for premium maps
class CesiumTokenManager extends StatefulWidget {
  final VoidCallback? onTokenChanged;
  
  const CesiumTokenManager({
    super.key,
    this.onTokenChanged,
  });

  @override
  State<CesiumTokenManager> createState() => _CesiumTokenManagerState();
}

class _CesiumTokenManagerState extends State<CesiumTokenManager> {
  String? _currentToken;
  bool _isTokenValidated = false;
  DateTime? _validationDate;
  bool _isValidating = false;
  bool _isLoading = true;
  
  final _tokenController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadCurrentToken();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentToken() async {
    try {
      final token = await PreferencesHelper.getCesiumUserToken();
      final validated = await PreferencesHelper.getCesiumTokenValidated() ?? false;
      final validationDate = await PreferencesHelper.getCesiumTokenValidationDate();
      
      if (mounted) {
        setState(() {
          _currentToken = token;
          _isTokenValidated = validated;
          _validationDate = validationDate;
          _isLoading = false;
        });
      }
    } catch (e) {
      LoggingService.error('CesiumTokenManager', 'Failed to load token: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _validateAndSaveToken(String token) async {
    if (!mounted) return;
    
    setState(() {
      _isValidating = true;
    });

    try {
      LoggingService.info('Validating Cesium Ion token...');
      final isValid = await CesiumTokenValidator.validateToken(token);
      
      if (!mounted) return;

      if (isValid) {
        // Save token and mark as validated
        await PreferencesHelper.setCesiumUserToken(token);
        await PreferencesHelper.setCesiumTokenValidated(true);
        
        // Update state
        setState(() {
          _currentToken = token;
          _isTokenValidated = true;
          _validationDate = DateTime.now();
          _tokenController.clear();
        });
        
        LoggingService.info('Cesium Ion token validated and saved successfully');
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Token validated! Premium maps are now available.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
        
        // Notify parent about token change
        widget.onTokenChanged?.call();
        
      } else {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid token. Please check and try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      LoggingService.error('CesiumTokenManager', 'Error validating token: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error validating token. Please check your internet connection.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isValidating = false;
        });
      }
    }
  }

  Future<void> _removeToken() async {
    try {
      await PreferencesHelper.removeCesiumUserToken();
      
      if (mounted) {
        setState(() {
          _currentToken = null;
          _isTokenValidated = false;
          _validationDate = null;
          _tokenController.clear();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Token removed. Premium maps are no longer available.'),
            duration: Duration(seconds: 3),
          ),
        );
        
        // Notify parent about token change
        widget.onTokenChanged?.call();
      }
      
      LoggingService.info('Cesium Ion token removed');
    } catch (e) {
      LoggingService.error('CesiumTokenManager', 'Error removing token: $e');
    }
  }

  Future<void> _testToken() async {
    if (_currentToken == null) return;
    
    setState(() {
      _isValidating = true;
    });

    try {
      final isValid = await CesiumTokenValidator.validateToken(_currentToken!);
      
      if (mounted) {
        final message = isValid 
          ? 'Token is valid and working correctly.'
          : 'Token validation failed. It may be expired or have insufficient permissions.';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isValid ? Colors.green : Colors.red,
            duration: Duration(seconds: isValid ? 2 : 4),
          ),
        );
        
        if (isValid) {
          await PreferencesHelper.setCesiumTokenValidated(true);
          setState(() {
            _isTokenValidated = true;
            _validationDate = DateTime.now();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error testing connection. Check your internet connection.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isValidating = false;
        });
      }
    }
  }

  Future<void> _launchCesiumIon() async {
    const url = 'https://cesium.com/ion/signup';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      LoggingService.error('CesiumTokenManager', 'Failed to launch URL: $e');
    }
  }

  void _showTokenInputDialog() {
    _tokenController.clear();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Cesium Ion Token'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Paste your Cesium Ion access token below:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'Access Token',
                  hintText: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a token';
                  }
                  if (value.trim().length < 10) {
                    return 'Token appears to be too short';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _launchCesiumIon,
                icon: const Icon(Icons.help_outline),
                label: const Text('How to get a token'),
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
            onPressed: _isValidating ? null : () {
              if (_formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop();
                _validateAndSaveToken(_tokenController.text.trim());
              }
            },
            child: _isValidating 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Validate & Save'),
          ),
        ],
      ),
    );
  }

  void _showRemoveConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Token?'),
        content: const Text(
          'This will remove your Cesium Ion token and disable access to premium maps. '
          'You can add it back anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _removeToken();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  String get _tokenStatus {
    if (_currentToken == null) return 'No token configured';
    
    if (!_isTokenValidated) return 'Token not validated';
    
    if (_validationDate != null) {
      final hoursAgo = DateTime.now().difference(_validationDate!).inHours;
      if (hoursAgo < 1) {
        return 'Active (validated ${DateTime.now().difference(_validationDate!).inMinutes}m ago)';
      } else if (hoursAgo < 24) {
        return 'Active (validated ${hoursAgo}h ago)';
      } else {
        return 'Validation expired (>24h old)';
      }
    }
    
    return 'Active';
  }

  Color get _statusColor {
    if (_currentToken == null) return Colors.grey;
    if (!_isTokenValidated) return Colors.orange;
    
    if (_validationDate != null) {
      final hoursAgo = DateTime.now().difference(_validationDate!).inHours;
      if (hoursAgo >= 24) return Colors.orange;
    }
    
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _currentToken != null ? Icons.verified_user : Icons.lock,
                  color: _statusColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Premium Maps',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Status: $_tokenStatus',
              style: TextStyle(
                color: _statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            
            if (_currentToken != null) ...[
              const SizedBox(height: 8),
              Text(
                'Token: ${CesiumTokenValidator.maskToken(_currentToken!)}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
            
            const SizedBox(height: 12),
            const Text(
              'Premium maps (Bing Maps) require your own free Cesium Ion account. '
              'Get up to 5GB of map data per month at no cost.',
              style: TextStyle(fontSize: 14),
            ),
            
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_currentToken == null) ...[
                  FilledButton.icon(
                    onPressed: _showTokenInputDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Token'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _launchCesiumIon,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Get Free Account'),
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: _isValidating ? null : _testToken,
                    icon: _isValidating 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_protected_setup),
                    label: const Text('Test Connection'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showRemoveConfirmDialog,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove Token'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}