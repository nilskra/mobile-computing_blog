import 'package:computing_blog/data/repository/auth_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileViewModel extends ChangeNotifier {
  final AuthRepository _repository = AuthRepository.instance;
  
  // Lokaler State
  bool _isAuthenticated = false;
  
  // Listener Callbacks speichern für Dispose
  VoidCallback? _authListener;

  ProfileViewModel() {
    _init();
  }

  void _init() {
    _isAuthenticated = _repository.isAuthenticated.value;
    
    _authListener = () {
      _isAuthenticated = _repository.isAuthenticated.value;
      notifyListeners();
    };
    _repository.isAuthenticated.addListener(_authListener!);
  }

  @override
  void dispose() {
    if (_authListener != null) {
      _repository.isAuthenticated.removeListener(_authListener!);
    }
    super.dispose();
  }
  
  Future<void> login() async {
    try {
      final authUri = await _repository.initAuthFlow();

      // Force launch or check canLaunch first
      await launchUrl(authUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (kDebugMode) {
        print("Login Error: $e");
      }
    }
  }

  Future<void> logout() async {
    await _repository.logout();
  }
}