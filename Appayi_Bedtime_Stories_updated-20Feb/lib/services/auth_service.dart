// lib/services/auth_service.dart
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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
        await _gsi.initialize();

        // Interactive auth UI
        final account =
            await _gsi.authenticate(scopeHint: const ['email', 'profile']);

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
        await _ensureUserDocument(
            user, 'google'); // keep this so parental gates/settings work
      }
      return credential;
    } on FirebaseAuthException catch (e, st) {
      developer.log('FirebaseAuthException: ${e.code} ${e.message}',
          stackTrace: st);
      return null;
    } catch (e, st) {
      developer.log('Unexpected sign-in error: $e', stackTrace: st);
      return null;
    }
  }

  // New: Sign in with Apple
  Future<UserCredential?> signInWithApple() async {
    try {
      // Only available on iOS/macOS, not web
      if (kIsWeb) {
        developer.log('Sign in with Apple not available on web');
        return null;
      }

      // Request credentials from Apple
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: WebAuthenticationOptions(
          clientId: 'com.your.app.service', // Replace with your service ID
          redirectUri: Uri.parse(
              'https://your-domain.com/callback'), // Replace with your redirect URI
        ),
      );

      // Create an OAuth credential for Firebase
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // Sign in to Firebase
      final userCredential = await _auth.signInWithCredential(oauthCredential);
      final user = userCredential.user;

      if (user != null) {
        // Update user info with Apple provided data if available
        String? displayName = user.displayName;
        if (appleCredential.givenName != null ||
            appleCredential.familyName != null) {
          displayName =
              '${appleCredential.givenName ?? ''} ${appleCredential.familyName ?? ''}'
                  .trim();
          if (displayName.isNotEmpty && user.displayName != displayName) {
            await user.updateDisplayName(displayName);
          }
        }

        await _ensureUserDocument(user, 'apple');
      }

      return userCredential;
    } on SignInWithAppleAuthorizationException catch (e) {
      developer
          .log('Apple sign-in authorization error: ${e.code} - ${e.message}');
      return null;
    } catch (e, st) {
      developer.log('Unexpected Apple sign-in error: $e', stackTrace: st);
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
      await Purchases.logOut();
      await _auth.signOut();
    } catch (e, st) {
      developer.log('Sign-out error: $e', stackTrace: st);
      rethrow;
    }
  }

  // Updated to accept provider parameter
  Future<void> _ensureUserDocument(User user, String provider) async {
    final ref = _db.collection('users').doc(user.uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final now = FieldValue.serverTimestamp();

      final base = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'provider': provider,
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

  // Future<UserCredential?> signInWithGoogle() async {
  //   try {
  //     UserCredential credential;

  //     if (kIsWeb) {
  //       // Web popup flow stays the same
  //       final provider = GoogleAuthProvider()
  //         ..addScope('email')
  //         ..addScope('profile')
  //         ..setCustomParameters({'prompt': 'select_account'});
  //       credential = await _auth.signInWithPopup(provider);
  //     } else {
  //       await _gsi.initialize();

  //       // Interactive auth UI
  //       final account =
  //           await _gsi.authenticate(scopeHint: const ['email', 'profile']);

  //       final tokenData = await account.authentication;
  //       final String? idToken = tokenData.idToken;

  //       if (idToken == null || idToken.isEmpty) {
  //         developer.log('Google sign-in failed: idToken is null/empty');
  //         return null;
  //       }

  //       final oauth = GoogleAuthProvider.credential(idToken: idToken);
  //       credential = await _auth.signInWithCredential(oauth);
  //     }

  //     final user = credential.user;
  //     if (user != null) {
  //       await _ensureUserDocument(
  //           user); // keep this so parental gates/settings work
  //     }
  //     return credential;
  //   } on FirebaseAuthException catch (e, st) {
  //     developer.log('FirebaseAuthException: ${e.code} ${e.message}',
  //         stackTrace: st);
  //     return null;
  //   } catch (e, st) {
  //     developer.log('Unexpected sign-in error: $e', stackTrace: st);
  //     return null;
  //   }
  // }

  // Future<void> signOut() async {
  //   try {
  //     if (!kIsWeb) {
  //       // Best-effort; ignore failures.
  //       await _gsi.signOut().catchError((_) {});
  //       await _gsi.disconnect().catchError((_) {});
  //     }
  //     await Purchases.logOut();
  //     await _auth.signOut();
  //   } catch (e, st) {
  //     developer.log('Sign-out error: $e', stackTrace: st);
  //     rethrow;
  //   }
  // }

  // Future<void> _ensureUserDocument(User user) async {
  //   final ref = _db.collection('users').doc(user.uid);
  //   await _db.runTransaction((tx) async {
  //     final snap = await tx.get(ref);
  //     final now = FieldValue.serverTimestamp();

  //     final base = <String, dynamic>{
  //       'uid': user.uid,
  //       'email': user.email,
  //       'displayName': user.displayName,
  //       'photoURL': user.photoURL,
  //       'provider': 'google',
  //       'lastLoginAt': now,
  //     };

  //     if (!snap.exists) {
  //       tx.set(ref, {
  //         ...base,
  //         'createdAt': now,
  //         'isProfileComplete': false,
  //         'language': null,
  //       });
  //     } else {
  //       tx.update(ref, base);
  //     }
  //   });
  // }


