import 'package:firebase_auth/firebase_auth.dart';

class UserIdentityService {
  UserIdentityService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Future<User> ensureSignedIn() async {
    final current = _auth.currentUser;
    if (current != null) return current;

    final credential = await _auth.signInAnonymously();
    final user = credential.user;
    if (user == null) {
      throw StateError('Firebase anonymous sign-in did not return a user.');
    }
    return user;
  }
}
