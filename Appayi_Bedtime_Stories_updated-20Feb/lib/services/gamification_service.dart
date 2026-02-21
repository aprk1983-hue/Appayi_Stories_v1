// lib/services/gamification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audio_story_app/screens/rewards_screen.dart'; // Import to get badge definitions

// A simple class to tell the UI what reward to show
class GamificationReward {
  final String title;
  final String message;
  GamificationReward({required this.title, required this.message});
}

class GamificationService {
  GamificationService._();
  static final instance = GamificationService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>>? _getUserRef() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid);
  }

  /// This is the main function you'll call when a story is finished.
  Future<List<GamificationReward>> handleStoryCompleted(String storyId, String category) async {
    final userRef = _getUserRef();
    if (userRef == null) return []; // Not logged in

    List<GamificationReward> newRewards = [];

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(userRef);
      final data = snap.data() ?? {};

      // --- 1. Get current progress from Firestore ---
      final int storiesListenedCount = (data['storiesListenedCount'] ?? 0) as int;
      final List<String> unlockedGems = (data['unlockedGems'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      final List<String> unlockedBadges = (data['unlockedBadges'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      final List<String> categoriesListened = (data['categoriesListened'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();

      Map<String, dynamic> updates = {}; // Data to save back to Firestore

      // --- 2. Gem Collection Logic ---
      if (!unlockedGems.contains(storyId)) {
        unlockedGems.add(storyId);
        updates['unlockedGems'] = unlockedGems;
        
        newRewards.add(GamificationReward(
          title: 'Gem Unlocked!',
          message: 'You collected a new gem for your collection!',
        ));

        // Check for "Gem Collector" badge
        if (unlockedGems.length == 10 && !unlockedBadges.contains('gem_collector_10')) {
          unlockedBadges.add('gem_collector_10');
          final badge = Badge.allBadges['gem_collector_10']!;
          newRewards.add(GamificationReward(
            title: 'Badge Unlocked!',
            message: '${badge.name}: ${badge.description}',
          ));
        }
      }

      // --- 3. Milestone Count Logic ---
      final newStoriesCount = storiesListenedCount + 1;
      updates['storiesListenedCount'] = newStoriesCount;
      
      // --- 4. Milestone Badge Logic ---
      // This map makes it easy to check all listen-count badges
      final Map<int, String> listenMilestones = {
        1: 'listened_1',
        5: 'listened_5',
        10: 'listened_10',
        15: 'listened_15',
        20: 'listened_20',
        50: 'listened_50',
        100: 'listened_100',
        150: 'listened_150',
        200: 'listened_200',
        250: 'listened_250',
        300: 'listened_300',
        350: 'listened_350',
        400: 'listened_400',
        450: 'listened_450',
        500: 'listened_500',
      };

      // Check if the new count hits any milestone
      if (listenMilestones.containsKey(newStoriesCount)) {
        final badgeId = listenMilestones[newStoriesCount]!;
        if (!unlockedBadges.contains(badgeId)) {
          unlockedBadges.add(badgeId);
          final badge = Badge.allBadges[badgeId]!;
          newRewards.add(GamificationReward(
            title: 'Badge Unlocked!',
            message: '${badge.name}: ${badge.description}',
          ));
        }
      }

      // --- 5. Explorer Badge Logic ---
      if (category.isNotEmpty && !categoriesListened.contains(category)) {
        categoriesListened.add(category);
        updates['categoriesListened'] = categoriesListened;
        
        if (categoriesListened.length == 3 && !unlockedBadges.contains('explorer_3')) {
          unlockedBadges.add('explorer_3');
          final badge = Badge.allBadges['explorer_3']!;
          newRewards.add(GamificationReward(
            title: 'Badge Unlocked!',
            message: '${badge.name}: ${badge.description}',
          ));
        }
      }
      
      updates['unlockedBadges'] = unlockedBadges;
      
      if (updates.isNotEmpty) {
        transaction.set(userRef, updates, SetOptions(merge: true));
      }
    });

    return newRewards;
  }
}