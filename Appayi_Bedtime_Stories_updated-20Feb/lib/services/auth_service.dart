// lib/services/auth_service.dart
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google Sign-In + Firestore profile bootstrap (web + mobile).
/// Updated for google_sign_in 7.x API:
/// - Uses GoogleSignIn.instance + initialize() + authenticate()
/// - Uses idToken only (accessToken no longer provided on 7.x)
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // New singleton access for v7.x
  final GoogleSignIn _gsi = GoogleSignIn.instance;

  Stream<User?> get user => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithGoogle() async {
    try {
      UserCredential credential;

      if (kIsWeb) {
        // Web popup flow stays the same
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile')
          ..setCustomParameters({'prompt': 'select_account'});
        credential = await _auth.signInWithPopup(provider);
      } else {
        // Mobile flow for google_sign_in 7.x
        // Optionally pass clientId/serverClientId if you need them;
        // for most Firebase setups defaults work as long as SHA certs are configured.
        await _gsi.initialize();

        // Interactive auth UI
        final account = await _gsi.authenticate(scopeHint: const ['email', 'profile']);

        // v7.x returns only idToken via GoogleSignInAuthentication
        final tokenData = await account.authentication;
        final String? idToken = tokenData.idToken;

        if (idToken == null || idToken.isEmpty) {
          developer.log('Google sign-in failed: idToken is null/empty');
          return null;
        }

        final oauth = GoogleAuthProvider.credential(idToken: idToken);
        credential = await _auth.signInWithCredential(oauth);
      }

      final user = credential.user;
      if (user != null) {
        await _ensureUserDocument(user); // keep this so parental gates/settings work
      }
      return credential;
    } on FirebaseAuthException catch (e, st) {
      developer.log('FirebaseAuthException: ${e.code} ${e.message}', stackTrace: st);
      return null;
    } catch (e, st) {
      developer.log('Unexpected sign-in error: $e', stackTrace: st);
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        // Best-effort; ignore failures.
        await _gsi.signOut().catchError((_) {});
        await _gsi.disconnect().catchError((_) {});
      }
      await _auth.signOut();
    } catch (e, st) {
      developer.log('Sign-out error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> _ensureUserDocument(User user) async {
    final ref = _db.collection('users').doc(user.uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final now = FieldValue.serverTimestamp();

      final base = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'provider': 'google',
        'lastLoginAt': now,
      };

      if (!snap.exists) {
        tx.set(ref, {
          ...base,
          'createdAt': now,
          'isProfileComplete': false,
          'language': null,
        });
      } else {
        tx.update(ref, base);
      }
    });
  }
}
