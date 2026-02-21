// lib/screens/story_player_screen.dart
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:just_audio/just_audio.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';

import 'package:audio_service/audio_service.dart';
import 'package:audio_story_app/services/app_audio_service.dart';

import '../models/story_model.dart';

// --- FIXED IMPORTS (Changed '.' to ':' after package) ---
import 'package:audio_story_app/services/parental_service.dart';
import 'package:audio_story_app/widgets/parent_gate.dart' as gate;
import 'package:audio_story_app/services/gamification_service.dart';
import 'package:audio_story_app/widgets/reward_dialog.dart';
import 'package:audio_story_app/screens/parental_controls_screen.dart';
import 'package:audio_story_app/widgets/app_loaders.dart';

final RouteObserver<PageRoute<dynamic>> appRouteObserver = RouteObserver<PageRoute<dynamic>>();
final ValueNotifier<bool> isStoryPlayerOnTop = ValueNotifier<bool>(false);

// No-animation route to avoid flicker when opening/closing the player.
Route<void> storyPlayerRoute(String storyId) {
  return PageRouteBuilder<void>(
    pageBuilder: (context, animation, secondaryAnimation) =>
        StoryPlayerScreen(storyId: storyId),
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
  );
}

/* --------------------------------------------------------------------------
 * Story badge helpers
 * --------------------------------------------------------------------------
 * Some stories may store story number in Firestore as a String ("01"),
 * a num (1.0), or under a different key (storyNumber, story_no, etc).
 * We normalize it here so the LANG+NO badge always shows correctly.
 */

int? _coerceInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    final direct = int.tryParse(s);
    if (direct != null) return direct;
    final m = RegExp(r'\d+').firstMatch(s);
    if (m != null) return int.tryParse(m.group(0)!);
  }
  return null;
}

int? _storyNoFromData(Map<String, dynamic>? data) {
  if (data == null) return null;
  final v = data['storyNo'] ??
      data['story_no'] ??
      data['storyNumber'] ??
      data['story_number'] ??
      data['number'] ??
      data['no'];
  return _coerceInt(v);
}

String? _langFromData(Map<String, dynamic>? data, {String? fallback}) {
  final v = (data?['language'] ?? data?['lang'] ?? fallback)?.toString();
  if (v == null) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}


class StoryPlayerScreen extends StatefulWidget {
  final String storyId;
  const StoryPlayerScreen({Key? key, required this.storyId}) : super(key: key);

  @override
  State<StoryPlayerScreen> createState() => _StoryPlayerScreenState();
}

class _StoryPlayerScreenState extends State<StoryPlayerScreen> with RouteAware {
  // ---------- Layout & theme ----------
  static const double kHorzPad = 20;
  static const double kVGapXS = 6;
  static const double kVGapS = 10;
  static const double kVGapM = 14;
  static const double kVGapL = 20;

  static const Color kAccentCyan = Color(0xFF00FFFF);
  static const Color kAccentOrange = Color(0xFFFFA726);
  final Color _neumorphicBase = Colors.black;

  final _auth = FirebaseAuth.instance;
  // Firestore document id for this story (used for navigation + now-playing extras).
  String _storyDocId = '';
  DocumentSnapshot<Map<String, dynamic>>? _currentStorySnap;
  // IMPORTANT: Use the single shared player from AppAudioService so that
  // StoryPlayerScreen, the mini-player, and notification controls are always in sync.
  final AudioPlayer _audioPlayer = AppAudioService.player;

  Story? _story;
  bool _loading = true;

  // Badge overrides (for cases where Story.fromFirestore doesn't decode
  // storyNo/language due to type/key differences in newer docs).
  int? _storyNoOverride;
  String? _langOverride;

  List<StoryScriptItem> _typedAudioScript = [];

  // Indices in the playlist that correspond to actual AUDIO segments (not prompts/silence).
  // Used so notification skipNext/skipPrevious can jump between audio segments only.
  List<int> _audioSegmentIndices = <int>[];

  String? _descriptionStr;
  Timestamp? _createdAtTs;
  int _views = 0;

  String? _coverHttps;

  String? _currentPrompt;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<ProcessingState>? _stateSub;

  int _likes = 0;
  int _dislikes = 0;
  int _myReaction = 0;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _aggSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _myReactSub;

  int _commentsCount = 0;
  final TextEditingController _commentCtrl = TextEditingController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _commentsCountSub;

  String? _currentUserPhotoUrl;
  Stream<DocumentSnapshot<Map<String, dynamic>>?>? _topCommentStream;

  // Composer state (main screen)
  bool _emojiMode = true;     // true = emojis, false = phrases
  bool _pickerOpen = false;     // NEW: start collapsed
  static const List<String> _emojis = [
    '😊','😄','👍','👏','❤️','🎉','🤩','🤗','🐶','🌟','💫','🙌'
  ];
  static const List<String> _nicePhrases = [
    'Loved it!',
    'That was fun!',
    'Amazing story!',
    'Made me smile 😊',
    'Great lesson!',
    'So cute!',
    'Let’s hear it again!',
    'Awesome sounds!',
  ];

  // Adjacent stories
  String? _prevStoryId;
  String? _nextStoryId;

  late Stream<ParentalSettings> _settingsStream;
  ParentalSettings? _currentSettings;

  @override
  void initState() {
    super.initState();
    
    _settingsStream = ParentalService.instance.watch();

    _load();
    _loadCurrentUserProfile();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final hasPin = await ParentalService.instance.hasPin();
        if (!hasPin) {
          await gate.requireParentPin(
            context,
            reason: 'Create a Parent PIN to protect comments & replies',
            forceSetupIfMissing: true,
          );
        }
      } catch (_) {}
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      isStoryPlayerOnTop.value = route.isCurrent;
    }
  }

  @override
  void didPush() {
    isStoryPlayerOnTop.value = true;
  }

  @override
  void didPopNext() {
    isStoryPlayerOnTop.value = true;
  }

  @override
  void didPushNext() {
    isStoryPlayerOnTop.value = false;
  }

  @override
  void didPop() {
    isStoryPlayerOnTop.value = false;
  }

  void _loadCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user != null) {
      final childData = await _getPreferredChildData(user);
      if (!mounted) return;
      setState(() {
        _currentUserPhotoUrl = childData['photoUrl'];
      });
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    isStoryPlayerOnTop.value = false;

    _indexSub?.cancel();
    _stateSub?.cancel();
    _aggSub?.cancel();
    _myReactSub?.cancel();
    _commentsCountSub?.cancel();
    _commentCtrl.dispose();
    // Do NOT dispose the shared AppAudioService player. Playback continues in mini player/notification.

    super.dispose();
  }
  
  // --- QUIET HOURS HELPER ---
  Future<bool> _isQuietHours() async {
    final settings = _currentSettings ?? await ParentalService.instance.get();
    
    TimeOfDay parseTime(String time) {
      try {
        final parts = time.split(':');
        return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {
        return const TimeOfDay(hour: 22, minute: 30);
      }
    }

    final startTime = parseTime(settings.quietStart);
    final endTime = parseTime(settings.quietEnd);
    final now = TimeOfDay.now();

    final nowInMinutes = now.hour * 60 + now.minute;
    final startInMinutes = startTime.hour * 60 + startTime.minute;
    final endInMinutes = endTime.hour * 60 + endTime.minute;

    if (startInMinutes > endInMinutes) {
      // Overnight window
      return nowInMinutes >= startInMinutes || nowInMinutes < endInMinutes;
    } else {
      // Daytime window
      return nowInMinutes >= startInMinutes && nowInMinutes < endInMinutes;
    }
  }

  
  // --- SNACKBAR HELPER (NOW A DIALOG) ---
  void _showQuietHoursSnackbar() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Shh... It's Bedtime now"),
          content: const Text(
            "The app is locked during quiet hours to help with bedtime.\n\nYou can change this schedule in Parental Controls.",
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            TextButton(
              child: const Text('Got it'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close the dialog
              },
            ),
            ElevatedButton(
              child: const Text('Go to Settings'),
              style: ElevatedButton.styleFrom(
                // This makes the button stand out
                backgroundColor: kAccentOrange, 
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close the dialog
                // Navigate to the Parental Controls screen
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ParentalControlsScreen(),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }


  Future<void> _load() async {
    try {
      final storiesCol = FirebaseFirestore.instance.collection('stories');
      final rawId = widget.storyId.trim();

      DocumentSnapshot<Map<String, dynamic>>? snap;

      if (rawId.contains('/')) {
        try {
          final direct = await FirebaseFirestore.instance.doc(rawId).get();
          if (direct.exists) snap = direct as DocumentSnapshot<Map<String, dynamic>>;
        } catch (_) {}
      }
      if (snap == null || !snap.exists) {
        try {
          final byDocId = await storiesCol.doc(rawId).get();
          if (byDocId.exists) snap = byDocId;
        } catch (_) {}
      }
      if (snap == null || !snap.exists) {
        final q1 = await storiesCol.where('id', isEqualTo: rawId).limit(1).get();
        if (q1.docs.isNotEmpty) snap = await q1.docs.first.reference.get();
      }
      if (snap == null || !snap.exists) {
        final q2 = await storiesCol.where('storyId', isEqualTo: rawId).limit(1).get();
        if (q2.docs.isNotEmpty) snap = await q2.docs.first.reference.get();
      }
      if (snap == null || !snap.exists) {
        final q3 = await storiesCol.where('slug', isEqualTo: rawId).limit(1).get();
        if (q3.docs.isNotEmpty) snap = await q3.docs.first.reference.get();
      }

      if (snap == null || !snap.exists) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Story not found for id: $rawId')),
        );
        return;
      }

      _storyDocId = snap.id;
      _currentStorySnap = snap;

      final story = Story.fromFirestore(snap);
      final data = snap.data() ?? {};

      // Ensure badge shows language + number even if Firestore stored storyNo
      // as a string ("01") or under a different key (storyNumber/story_no...).
      final int? storyNoOverride = _storyNoFromData(data);
      final String? langOverride = _langFromData(data, fallback: story.language);
      _descriptionStr =
          (data['description'] ?? data['shortDescription'] ?? data['desc'])?.toString();
      final ts = data['createdAt'];
      if (ts is Timestamp) _createdAtTs = ts;

      // --- ROBUST URL RESOLUTION ---
      _coverHttps = await _resolveUrl(story.coverImageUrl);


// Detect if this story is already loaded in the shared player (e.g., user tapped the mini player).
final currentMedia = AppAudioService.handler.mediaItem.valueOrNull;
final currentStoryId = (currentMedia?.extras?['storyId'] ?? currentMedia?.id)?.toString();
final thisStoryId = _storyDocId.isNotEmpty ? _storyDocId : rawId;
final bool alreadyLoaded = currentStoryId != null &&
    currentStoryId.isNotEmpty &&
    (currentStoryId == rawId || currentStoryId == thisStoryId || currentStoryId == story.id) &&
    _audioPlayer.audioSource != null;

// Build a playlist that preserves 1:1 index alignment with _typedAudioScript,
// so prompts/silence and audio indices match the currentIndex.
_audioSegmentIndices = <int>[];
final playlist = ConcatenatingAudioSource(children: []);
final List<StoryScriptItem> parsedScript = [];
for (final itemDynamic in story.audioScript) {
  if (itemDynamic is Map) {
    final item = StoryScriptItem.fromJson(itemDynamic as Map<String, dynamic>);
    parsedScript.add(item);
  }
}
_typedAudioScript = parsedScript;

int playlistIndex = 0;
for (final item in _typedAudioScript) {
  if (item.type == 'audio') {
    final playable = await _resolveUrl((item.audioUrl ?? '').trim());
    if (playable.isNotEmpty) {
      try {
        playlist.add(AudioSource.uri(Uri.parse(playable)));
        _audioSegmentIndices.add(playlistIndex);
      } catch (_) {
        // Keep alignment if URL is invalid.
        playlist.add(SilenceAudioSource(duration: Duration.zero));
      }
    } else {
      // Keep alignment if audio URL is missing.
      playlist.add(SilenceAudioSource(duration: Duration.zero));
    }
    playlistIndex++;
  } else if (item.type == 'prompt') {
    playlist.add(
      SilenceAudioSource(
        duration: Duration(milliseconds: item.pauseDurationMs ?? 2000),
        tag: item.text,
      ),
    );
    playlistIndex++;
  }
}

            if (playlist.children.isEmpty) {
        throw Exception('No playable audio sources found in story script.');
      }
      // Keep notification/mini-player skipNext/skipPrevious aligned with AUDIO segments.
      AppAudioService.handler.updateAudioSegmentIndices(_audioSegmentIndices);

      if (!alreadyLoaded) {
        await _audioPlayer.setAudioSource(playlist);
      }
      _wirePromptListeners();

      if (!mounted) return;
      setState(() {
        _story = story;
        _storyNoOverride = storyNoOverride;
        _langOverride = langOverride;
        _loading = false;
      });
      _syncMediaMeta();
      _syncMediaMeta();

      _listenRealtime(snap.reference);

      try {
        snap.reference.update({'views': FieldValue.increment(1)});
      } catch (_) {}

      _refreshNeighbors();

      if (!alreadyLoaded) {


        if (await _isQuietHours()) {


          _showQuietHoursSnackbar();


        } else {


          _audioPlayer.play();


        }


      }

    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load story: $e')),
      );
    }
  }

  Future<void> _refreshNeighbors() async {
    _prevStoryId = null;
    _nextStoryId = null;

    final snap = _currentStorySnap;
    final cat = _story?.category;
    final lang = (_story?.language ?? '').trim();

    if (snap == null || cat == null || cat.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('stories')
        .where('category', isEqualTo: cat);

    if (lang.isNotEmpty) {
      q = q.where('language', isEqualTo: lang);
    }

    // Use the SAME descending order for both directions and cursor around the current doc,
    // so we don't rely on a separate ascending composite index.
    q = q.orderBy('createdAt', descending: true);

    try {
      final olderSnap = await q.startAfterDocument(snap).limit(1).get(); // older => NEXT
      final newerSnap = await q.endBeforeDocument(snap).limit(1).get();  // newer => PREV

      if (!mounted) return;
      setState(() {
        _prevStoryId = newerSnap.docs.isNotEmpty ? newerSnap.docs.first.id : null;
        _nextStoryId = olderSnap.docs.isNotEmpty ? olderSnap.docs.first.id : null;
      });

      _syncMediaMeta();
    } catch (_) {
      if (mounted) setState(() {});
    }
  }


  void _syncMediaMeta() {
    final story = _story;
    if (story == null) return;
    try {
      final cover = (_coverHttps ?? story.coverImageUrl).toString();
      final art = cover.isNotEmpty ? Uri.tryParse(cover) : null;

      AppAudioService.handler.mediaItem.add(
        MediaItem(
          id: (_storyDocId.isNotEmpty ? _storyDocId : story.id),
          title: story.title,
          artist: (story.category ?? '').toString(),
          artUri: art,
          extras: {
            'storyId': (_storyDocId.isNotEmpty ? _storyDocId : story.id),
            'coverUrl': cover,
            'prevStoryId': _prevStoryId,
            'nextStoryId': _nextStoryId,
            'category': story.category,
            'language': story.language,
          },
        ),
      );
    } catch (_) {
      // ignore
    }
  }

  void _openStoryById(String id) {
    _audioPlayer.stop();
    Navigator.pushReplacement(
      context,
      storyPlayerRoute(id),
    );
  }

  void _wirePromptListeners() {
    _indexSub = _audioPlayer.currentIndexStream.listen((index) {
      if (index == null || _typedAudioScript.isEmpty) return;
      if (index >= _typedAudioScript.length) return; 
      final current = _typedAudioScript[index];
      setState(() => _currentPrompt = current.type == 'prompt' ? current.text : null);
    });
    _stateSub = _audioPlayer.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        if (mounted) setState(() => _currentPrompt = "The End!");
        await _triggerRewards();
        final nextId = _nextStoryId;
        if (nextId != null && nextId.isNotEmpty && mounted) {
          await Future.delayed(const Duration(milliseconds: 250));
          if (mounted) _openStoryById(nextId);
        }
      }
    });
  }
  
  Future<void> _triggerRewards() async {
    if (_story == null) return;
    
    final rewards = await GamificationService.instance.handleStoryCompleted(
      _story!.id,
      _story!.category ?? '',
    );

    if (mounted && rewards.isNotEmpty) {
      for (final reward in rewards) {
        await showRewardDialog(context, reward.title, reward.message);
      }
    }
  }

  void _listenRealtime(DocumentReference<Map<String, dynamic>> storyRef) {
    _aggSub = storyRef.snapshots().listen((doc) {
      if (!doc.exists) return;
      final d = doc.data()!;
      setState(() {
        _likes = (d['likes'] is int) ? d['likes'] as int : 0;
        _dislikes = (d['dislikes'] is int) ? d['dislikes'] as int : 0;
        _views = (d['views'] is int) ? d['views'] as int : _views;
      });
    });

    final user = _auth.currentUser;
    if (user != null) {
      final myRef = storyRef.collection('likes').doc(user.uid);
      _myReactSub = myRef.snapshots().listen((doc) {
        setState(() => _myReaction = (doc.data()?['value'] ?? 0) as int);
      });
    }

    _commentsCountSub = storyRef.collection('comments').snapshots().listen((qs) {
      setState(() => _commentsCount = qs.size);
    });

    _topCommentStream = storyRef
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((qs) => qs.docs.isNotEmpty
            ? qs.docs.first as DocumentSnapshot<Map<String, dynamic>>
            : null);
  }

  // --- ROBUST URL HELPER ---
  Future<String> _resolveUrl(String path) async {
    final p = path.trim(); // IMPORTANT: trim whitespace
    if (p.isEmpty) return '';

    // 1. If it's already a public HTTPS URL (like Cloudflare), just return it.
    if (p.startsWith('https://')) {
      return p;
    }
    // 2. If it's HTTP, convert to HTTPS.
    if (p.startsWith('http://')) {
      return 'https://${p.substring(7)}';
    }
    // 3. If it's a Firebase Storage (gs://) path, resolve it.
    if (p.startsWith('gs://')) {
      try {
        final ref = FirebaseStorage.instance.refFromURL(p);
        return await ref.getDownloadURL();
      } catch (_) {
        return ''; // Failed to get URL
      }
    }
    // 4. If it's none of the above, it's an invalid path.
    return '';
  }

  // Helper method kept for compatibility if needed, otherwise _resolveUrl replaces it
  Future<String> _toHttps(String path) => _resolveUrl(path);
  Future<String> _toHttpsOrPassthrough(String url) => _resolveUrl(url);


  String _fmtTsDdMmmYyyy(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  String _fmtInt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      buf.write(s[i]);
      final remain = s.length - i - 1;
      if (remain > 0 && remain % 3 == 0) buf.write(',');
    }
    return buf.toString();
  }

  Future<void> _share() async {
    final ps = _currentSettings ?? await ParentalService.instance.get();
    if (ps.childMode) {
      final ok = await gate.requireParentPin(context, reason: 'Share this story');
      if (!ok) return;
    }
    try {
      await Clipboard.setData(
        ClipboardData(text: 'Check out this story: ${_story?.title ?? ''}'),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied!')),
        );
      }
    } catch (_) {}
  }

  // ---------- Comment helpers ----------
  Future<Map<String, String?>> _getPreferredChildData(User user) async {
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = snap.data();

    String? preferredDisplayName = user.displayName;
    String? preferredPhotoUrl;

    if (data != null) {
      final childData =
          (data['child'] is Map) ? data['child'] as Map<String, dynamic> : null;

      final photo = (childData?['photoUrl'] ?? data['profileImageUrl'])?.toString();
      final nick =
          (childData?['nickName'] ?? data['childNickname'])?.toString();

      if (nick != null && nick.isNotEmpty) {
        preferredDisplayName = nick;
      }
      if (photo != null && photo.isNotEmpty) {
        preferredPhotoUrl = photo;
      }
    }

    preferredDisplayName ??= user.email ?? 'User';

    return {
      'displayName': preferredDisplayName,
      'photoUrl': preferredPhotoUrl,
    };
  }

  Future<void> _postComment() async {
    final settings = _currentSettings;
    if (settings == null) return;

    final user = _auth.currentUser;
    if (user == null || _story == null) return;

    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    
    if (!settings.commentsEnabled) {
      final ok = await gate.requireParentPinOnce(context, reason: 'Post a comment');
      if (!ok) return;
    }

    try {
      final childData = await _getPreferredChildData(user);
      await FirebaseFirestore.instance
          .collection('stories')
          .doc(_story!.id)
          .collection('comments')
          .add({
        'uid': user.uid,
        'displayName': childData['displayName'] ?? (user.displayName ?? user.email ?? 'User'),
        'photoUrl': childData['photoUrl'],
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': 0,
        'isAdmin': false,
      });

      _commentCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment posted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post comment: $e')),
      );
    }
  }

  Future<void> _addToPlaylist() async {
    final user = _auth.currentUser;
    final s = _story;
    if (user == null || s == null) return;

    final itemsCol = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('playlists')
        .doc('default')
        .collection('items');

    try {
      await itemsCol.doc(s.id).set({
        'title': s.title,
        'coverImageUrl': s.coverImageUrl,
        'category': s.category,
        'addedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to playlist')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add to playlist: $e')),
      );
    }
  }

  void _showCommentsModal() {
    if (_story == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CommentsBottomSheet(
        storyRef:
            FirebaseFirestore.instance.collection('stories').doc(_story!.id),
        commentsCount: _commentsCount,
      ),
    );
  }

  
Widget _buildControlsCard({required bool playing}) {
  const border = Color(0xFF4FC3F7); // sky/blue
  return Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border.withOpacity(0.95), width: 1.6),
        boxShadow: [
          BoxShadow(
            color: border.withOpacity(0.35),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MiniCtl(
              icon: Icons.share_rounded,
              size: 40,
              onTap: _share,
            ),
            const SizedBox(width: 10),
            _MiniCtl(
              icon: Icons.skip_previous_rounded,
              size: 46,
              onTap: (_prevStoryId != null) ? () => _openStoryById(_prevStoryId!) : null,
              disabled: _prevStoryId == null,
            ),
            const SizedBox(width: 12),
            _MiniCtl(
              icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 58,
              isPrimary: true,
              onTap: () async {
                if (playing) {
                  _audioPlayer.pause();
                } else {
                  if (await _isQuietHours()) {
                    _showQuietHoursSnackbar();
                  } else {
                    _audioPlayer.play();
                  }
                }
              },
            ),
            const SizedBox(width: 12),
            _MiniCtl(
              icon: Icons.skip_next_rounded,
              size: 46,
              onTap: (_nextStoryId != null) ? () => _openStoryById(_nextStoryId!) : null,
              disabled: _nextStoryId == null,
            ),
            const SizedBox(width: 10),
            _MiniCtl(
              icon: Icons.playlist_add_rounded,
              size: 40,
              onTap: _addToPlaylist,
            ),
          ],
        ),
      ),
    ),
  );
}

@override
  Widget build(BuildContext context) {
    final onBg = Colors.white;

    return Scaffold(
      backgroundColor: _neumorphicBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: true,
      ),
      body: StreamBuilder<ParentalSettings>(
        stream: _settingsStream,
        builder: (context, settingsSnap) {
          
          if (_loading || !settingsSnap.hasData) {
            return const Center(child: AppLoader());
          }
          
          _currentSettings = settingsSnap.data;

          if (_story == null) {
            return Center(child: Text('Story not found', style: TextStyle(color: onBg)));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(kHorzPad, 8, kHorzPad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: widget.storyId,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CachedNetworkImage(
                              imageUrl: _coverHttps ?? '',
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  Container(color: Colors.grey[800]),
                              errorWidget: (context, url, error) =>
                                  Container(color: Colors.grey[800]),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            bottom: 12,
                            child: _LangNoBadge(
                              language: (_story?.language != null &&
                                      _story!.language!.trim().isNotEmpty)
                                  ? _story!.language
                                  : _langOverride,
                              storyNo: _story?.storyNo ?? _storyNoOverride,
                              scale: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: kVGapL),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _story!.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ReactionButton(
                          icon: Icons.thumb_up_alt_rounded,
                          label: '${_fmtInt(_likes)} Like',
                          selected: _myReaction == 1,
                          onTap: () => _setReaction(1),
                          color: kAccentOrange,
                        ),
                        const SizedBox(width: 24),
                        _ReactionButton(
                          icon: Icons.thumb_down_alt_rounded,
                          label: 'Dislike',
                          selected: _myReaction == -1,
                          onTap: () => _setReaction(-1),
                          color: kAccentOrange,
                          showCount: false,
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: kVGapM),

                Row(
                  children: [
                    Text('${_fmtInt(_views)} views', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 18)),
                    const SizedBox(width: 18),
                    Text(_fmtTsDdMmmYyyy(_createdAtTs), style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 18)),
                  ],
                ),

                const SizedBox(height: kVGapM),

                _SeekBar(player: _audioPlayer, isDark: true, activeColor: kAccentOrange),

                const SizedBox(height: kVGapS),

                StreamBuilder<PlayerState>(
                  stream: _audioPlayer.playerStateStream,
                  builder: (context, snap) {
                    final playing = snap.data?.playing ?? false;

                    final canPrevStory = _prevStoryId != null;
                    final canNextStory = _nextStoryId != null;

                    const glowBlue = Color(0xFF00E5FF);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: kVGapM),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: glowBlue.withOpacity(0.85),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: glowBlue.withOpacity(0.30),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _NeumorphicControl(
                                  onTap: _share,
                                  baseColor: _neumorphicBase,
                                  accentColor: glowBlue,
                                  icon: Icons.share_rounded,
                                  size: 34,
                                  iconSize: 18,
                                ),
                                const SizedBox(width: 8),
                                _NeumorphicControl(
                                  onTap: canPrevStory ? () => _openStoryById(_prevStoryId!) : null,
                                  baseColor: _neumorphicBase,
                                  accentColor: glowBlue,
                                  icon: Icons.skip_previous_rounded,
                                  size: 40,
                                  iconSize: 20,
                                  isDisabled: !canPrevStory,
                                ),
                                const SizedBox(width: 12),
                                _NeumorphicControl(
                                  onTap: () async {
                                    if (playing) {
                                      _audioPlayer.pause();
                                    } else {
                                      if (await _isQuietHours()) {
                                        _showQuietHoursSnackbar();
                                      } else {
                                        _audioPlayer.play();
                                      }
                                    }
                                  },
                                  baseColor: _neumorphicBase,
                                  accentColor: glowBlue,
                                  icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  size: 56,
                                  iconSize: 30,
                                ),
                                const SizedBox(width: 12),
                                _NeumorphicControl(
                                  onTap: canNextStory ? () => _openStoryById(_nextStoryId!) : null,
                                  baseColor: _neumorphicBase,
                                  accentColor: glowBlue,
                                  icon: Icons.skip_next_rounded,
                                  size: 40,
                                  iconSize: 20,
                                  isDisabled: !canNextStory,
                                ),
                                const SizedBox(width: 8),
                                _NeumorphicControl(
                                  onTap: _addToPlaylist,
                                  baseColor: _neumorphicBase,
                                  accentColor: glowBlue,
                                  icon: Icons.playlist_add_rounded,
                                  size: 34,
                                  iconSize: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                if (_currentPrompt != null) ...[
                  const SizedBox(height: kVGapM),
                  Text(
                    _currentPrompt!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],

                const SizedBox(height: kVGapL),

                Text(
                  (_descriptionStr != null && _descriptionStr!.trim().isNotEmpty)
                      ? _descriptionStr!.trim()
                      : '—',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.normal,
                  ),
                ),

                const SizedBox(height: kVGapL),

                GestureDetector(
                  onTap: _showCommentsModal,
                  child: _CommentPreviewCard(
                    commentsCount: _commentsCount,
                    topCommentStream: _topCommentStream,
                  ),
                ),
                const SizedBox(height: kVGapM),
                
                _ComposerCard(
                  photoUrl: _currentUserPhotoUrl,
                  controller: _commentCtrl,
                  emojiMode: _emojiMode,
                  pickerOpen: _pickerOpen, 
                  onToggleType: (bool emojiSelected) { 
                    setState(() {
                      if (_pickerOpen && _emojiMode == emojiSelected) {
                        _pickerOpen = false; 
                      } else {
                        _emojiMode = emojiSelected;
                        _pickerOpen = true; 
                      }
                    });
                  },
                  onPickEmoji: (s) => setState(() {
                    _commentCtrl.text = (_commentCtrl.text + (_commentCtrl.text.isEmpty ? '' : ' ') + s).trimLeft();
                  }),
                  onPickPhrase: (s) => setState(() {
                    _commentCtrl.text = s;
                  }),
                  emojis: _emojis,
                  phrases: _nicePhrases,
                  onSend: _postComment,
                ),

                if ((_story?.category?.isNotEmpty ?? false) && _createdAtTs != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'More in ${_story!.category}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MoreInCategoryStrip(
                    category: _story!.category!,
                    language: _story!.language ?? '', // <-- Pass language
                    before: _createdAtTs!,
                    onOpen: _openStoryById,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _setReaction(int newValue) async {
    final user = _auth.currentUser;
    if (user == null || _story == null) return;

    final storyRef =
        FirebaseFirestore.instance.collection('stories').doc(_story!.id);
    final myRef = storyRef.collection('likes').doc(user.uid);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final mySnap = await tx.get(myRef);
      final prev = (mySnap.data()?['value'] ?? 0) as int;
      final apply = (prev == newValue) ? 0 : newValue;

      int likeDelta = 0;
      int dislikeDelta = 0;
      if (prev == 1) likeDelta -= 1;
      if (prev == -1) dislikeDelta -= 1;
      if (apply == 1) likeDelta += 1;
      if (apply == -1) dislikeDelta += 1;

      tx.set(
        myRef,
        {'value': apply, 'updatedAt': FieldValue.serverTimestamp(), 'uid': user.uid},
        SetOptions(merge: true),
      );
      tx.set(
        storyRef,
        {
          if (likeDelta != 0) 'likes': FieldValue.increment(likeDelta),
          if (dislikeDelta != 0) 'dislikes': FieldValue.increment(dislikeDelta),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
}


class _MiniCtl extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onTap;
  final bool disabled;
  final bool isPrimary;

  const _MiniCtl({
    required this.icon,
    required this.size,
    required this.onTap,
    this.disabled = false,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final border = const Color(0xFF4FC3F7);
    final bg = isPrimary ? border.withOpacity(0.20) : Colors.white10;
    final iconColor = disabled ? Colors.white24 : Colors.white;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: border.withOpacity(isPrimary ? 0.9 : 0.55), width: isPrimary ? 1.6 : 1.2),
          boxShadow: [
            BoxShadow(
              color: border.withOpacity(isPrimary ? 0.35 : 0.18),
              blurRadius: isPrimary ? 18 : 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(icon, color: iconColor, size: size * 0.55),
      ),
    );
  }
}

/* ================================================================
    UI widgets
   ================================================================ */

class _ReactionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final bool showCount;

  const _ReactionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
    this.showCount = true,
  });

  @override
  Widget build(BuildContext context) {
    final List<BoxShadow> shadow = [
      BoxShadow(
        color: Colors.black.withOpacity(0.35),
        blurRadius: 8,
        offset: const Offset(3, 4),
      ),
      if (selected)
        BoxShadow(
          color: color.withOpacity(0.35),
          blurRadius: 14,
          spreadRadius: 0.5,
        ),
    ];

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1E1E1E),
              boxShadow: shadow,
            ),
            child: Icon(
              icon,
              size: 18,
              color: selected ? color : Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NeumorphicControl extends StatelessWidget {
  final VoidCallback? onTap;
  final Color baseColor;
  final Color accentColor;
  final IconData icon;
  final double size;
  final double iconSize;
  final bool isDisabled;

  const _NeumorphicControl({
    super.key,
    required this.onTap,
    required this.baseColor,
    required this.accentColor,
    required this.icon,
    required this.size,
    required this.iconSize,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final double shadowDepth = size * 0.1;
    final Color iconColor =
        isDisabled ? accentColor.withOpacity(0.3) : accentColor;

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: baseColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black54.withOpacity(0.5),
              offset: Offset(shadowDepth, shadowDepth),
              blurRadius: shadowDepth * 2,
            ),
            BoxShadow(
              color: Colors.white12,
              offset: Offset(-shadowDepth / 2, -shadowDepth / 2),
              blurRadius: shadowDepth,
            ),
            BoxShadow(
              color: accentColor.withOpacity(0.3),
              blurRadius: shadowDepth * 3,
              spreadRadius: -shadowDepth * 0.5,
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  final AudioPlayer player;
  final bool isDark;
  final Color activeColor;
  const _SeekBar({
    super.key,
    required this.player,
    required this.isDark,
    required this.activeColor,
  });

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    return hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, posSnap) {
        final pos = posSnap.data ?? Duration.zero;
        final total = player.duration ?? Duration.zero;

        final max = total.inMilliseconds.toDouble().clamp(0.0, double.infinity);
        final value = pos.inMilliseconds.toDouble().clamp(0.0, max);

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
              ),
              child: Slider(
                value: value,
                min: 0,
                max: (max == 0) ? 1 : max,
                onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                activeColor: activeColor,
                inactiveColor: Colors.white24,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(pos), style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  Text(_fmt(total), style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CommentPreviewCard extends StatelessWidget {
  final int commentsCount;
  final Stream<DocumentSnapshot<Map<String, dynamic>>?>? topCommentStream;

  const _CommentPreviewCard({
    super.key,
    required this.commentsCount,
    required this.topCommentStream,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Comments',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text('$commentsCount',
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
            stream: topCommentStream,
            builder: (context, snap) {
              if (topCommentStream == null ||
                  !snap.hasData || snap.data == null || !snap.data!.exists) {
                return const Text(
                  'Be the first to comment!',
                  style: TextStyle(color: Colors.white70),
                );
              }
              final data = snap.data!.data()!;
              final name = (data['displayName'] ?? 'User').toString();
              final text = (data['text'] ?? '').toString();
              final photoUrl = (data['photoUrl'] ?? '').toString();

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _UserAvatar(photoUrl: photoUrl, radius: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$name: $text',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ComposerCard extends StatelessWidget {
  final String? photoUrl;
  final TextEditingController controller;
  final bool emojiMode;                 // unchanged
  final bool pickerOpen;                // NEW
  final void Function(bool emojiSelected) onToggleType; // NEW
  final void Function(String) onPickEmoji;
  final void Function(String) onPickPhrase;
  final List<String> emojis;
  final List<String> phrases;
  final VoidCallback onSend;

  const _ComposerCard({
    super.key,
    required this.photoUrl,
    required this.controller,
    required this.emojiMode,
    required this.pickerOpen,          // NEW
    required this.onToggleType,        // NEW
    required this.onPickEmoji,
    required this.onPickPhrase,
    required this.emojis,
    required this.phrases,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _UserAvatar(photoUrl: photoUrl, radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  readOnly: true,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Tap 🙂 or ✍️ below to compose...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.white38),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(onPressed: onSend),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ChoiceChip(
                label: const Text('🙂 Emoji'),
                selected: pickerOpen && emojiMode,   // NEW
                onSelected: (_) => onToggleType(true), // NEW
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('✍️ Text'),
                selected: pickerOpen && !emojiMode,   // NEW
                onSelected: (_) => onToggleType(false),// NEW
              ),
            ],
          ),
          if (pickerOpen) ...[                // NEW: only show grid when open
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: emojiMode
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: emojis
                          .map((e) => _ChipPill(
                                label: e,
                                onTap: () => onPickEmoji(e),
                              ))
                          .toList(),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: phrases
                          .map((p) => _ChipPill(
                                label: p,
                                onTap: () => onPickPhrase(p),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ChipPill({super.key, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _SendButton({super.key, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: _StoryPlayerScreenState.kAccentOrange,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: const Padding(
          padding: EdgeInsets.all(10.0),
          child: Icon(Icons.send_rounded, color: Colors.black),
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final double radius;
  const _UserAvatar({super.key, this.photoUrl, required this.radius});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null &&
        photoUrl!.isNotEmpty &&
        (photoUrl!.startsWith('http') || photoUrl!.startsWith('https'))) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(photoUrl!));
    }

    final List<Color> _fallbackColors = [
      Colors.orange.shade400,
      Colors.green.shade400,
      Colors.pink.shade400,
      Colors.purple.shade400,
      Colors.cyan.shade400,
    ];
    final int colorIndex = radius.toInt() % _fallbackColors.length;

    return CircleAvatar(
      radius: radius,
      backgroundColor: _fallbackColors[colorIndex],
      child: Text('🙂', style: TextStyle(fontSize: radius)),
    );
  }
}

/* ===================== Comments & Replies Bottom Sheet ===================== */

class _CommentsBottomSheet extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> storyRef;
  final int commentsCount;
  const _CommentsBottomSheet(
      {super.key, required this.storyRef, required this.commentsCount});

  @override
  State<_CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<_CommentsBottomSheet> {
  static const int _pageSize = 10;
  List<DocumentSnapshot<Map<String, dynamic>>> _commentDocs = [];
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadMoreComments(isInitial: true);
  }

  void _onCommentDeleted(String id) {
    setState(() {
      _commentDocs.removeWhere((d) => d.id == id);
    });
  }

  Future<void> _loadMoreComments({bool isInitial = false}) async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    Query<Map<String, dynamic>> query = widget.storyRef
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    if (_commentDocs.isNotEmpty && !isInitial) {
      query = query.startAfterDocument(_commentDocs.last);
    }

    try {
      final snap = await query.get();
      if (!mounted) return;
      setState(() {
        _commentDocs.addAll(snap.docs);
        _hasMore = snap.docs.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color bg = Colors.black;
    const Color onBg = Colors.white;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 32),
                Text(
                  'Comments ${widget.commentsCount}',
                  style: const TextStyle(
                      color: onBg, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: onBg),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // List only (composer removed in sheet)
          const SizedBox(height: 6),

          Expanded(
            child: ListView.separated(
              itemCount: _commentDocs.length + (_hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                if (i == _commentDocs.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: _isLoading
                          ? const AppLoader(size: 34, color: onBg)
                          : TextButton(
                              onPressed: _loadMoreComments,
                              child: const Text('Load More (10)'),
                            ),
                    ),
                  );
                }

                final doc = _commentDocs[i];
                final data = doc.data()!;
                final currentUid = FirebaseAuth.instance.currentUser?.uid;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _CommentTile(
                    commentId: doc.id,
                    storyRef: widget.storyRef,
                    name: (data['displayName'] ?? 'User').toString(),
                    text: (data['text'] ?? '').toString(),
                    photoUrl: (data['photoUrl'] ?? '').toString(),
                    timestamp: data['createdAt'] as Timestamp?,
                    isAdmin: (data['isAdmin'] == true),
                    commentLikes:
                        (data['likes'] is int) ? data['likes'] as int : 0,
                    onReply: (parentCommentId, parentUserName) =>
                        _ReplyInputModal.show(
                      context,
                      storyRef: widget.storyRef,
                      parentCommentId: parentCommentId,
                      parentUserName: parentUserName,
                      currentUserPhotoUrl:
                          (FirebaseAuth.instance.currentUser?.photoURL ?? ''),
                    ),
                    canDelete: currentUid != null &&
                        (data['uid'] == currentUid ||
                         data['userId'] == currentUid ||
                         data['authorUid'] == currentUid),
                    onDeleted: _onCommentDeleted,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------ Comments list / tiles / replies ------------------ */

class _CommentTile extends StatelessWidget {
  final String commentId;
  final DocumentReference<Map<String, dynamic>> storyRef;
  final String name;
  final String text;
  final String? photoUrl;
  final Timestamp? timestamp;
  final bool isAdmin;
  final int commentLikes;
  final void Function(String, String) onReply;

  final bool canDelete;
  final void Function(String id)? onDeleted;

  const _CommentTile({
    super.key,
    required this.commentId,
    required this.storyRef,
    required this.name,
    required this.text,
    this.photoUrl,
    this.timestamp,
    this.isAdmin = false,
    required this.onReply,
    this.commentLikes = 0,
    this.canDelete = false,
    this.onDeleted,
  });

  String _getTimeAgo(Timestamp? ts) {
    if (ts == null) return '';
    return timeago.format(ts.toDate(), locale: 'en_short');
  }

  @override
  Widget build(BuildContext context) {
    final commentRef = storyRef.collection('comments').doc(commentId);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _UserAvatar(photoUrl: photoUrl, radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        const SizedBox(width: 8),
                        Text(_getTimeAgo(timestamp),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        if (isAdmin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade600,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Admin',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                        const Spacer(),
                        if (canDelete)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded,
                                size: 18, color: Colors.white70),
                            onSelected: (value) async {
                              if (value == 'delete') {
                                try {
                                  await commentRef.delete();
                                  onDeleted?.call(commentId);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Comment deleted')),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Delete failed: $e')),
                                  );
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Row(
                                  children: const [
                                    Icon(Icons.delete_outline,
                                        color: _StoryPlayerScreenState.kAccentOrange, size: 20),
                                    SizedBox(width: 8),
                                    Text('Delete',
                                        style: TextStyle(
                                          color: _StoryPlayerScreenState.kAccentOrange,
                                          fontWeight: FontWeight.w600,
                                        )),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(text,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.normal,
                            fontSize: 15)),
                    const SizedBox(height: 8),

                    // Reply action (gated)
                    GestureDetector(
                      onTap: () async {
                        final settings = await ParentalService.instance.get();
                        if (!settings.commentsEnabled) {
                          final ok = await gate.requireParentPinOnce(
                            context,
                            reason: 'Reply to a comment',
                          );
                          if (!ok) return;
                        }
                        onReply(commentId, name);
                      },
                      child: Text('Reply...',
                          style: TextStyle(
                              color: Colors.white70.withOpacity(0.8),
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _NestedRepliesList(commentRef: commentRef, parentUserName: name),
        ],
      ),
    );
  }
}

class _NestedRepliesList extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> commentRef;
  final String parentUserName;

  const _NestedRepliesList(
      {required this.commentRef, required this.parentUserName});

  String _getTimeAgo(Timestamp? ts) {
    if (ts == null) return '';
    return timeago.format(ts.toDate(), locale: 'en_short');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          commentRef.collection('replies').orderBy('createdAt').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final replies = snap.data!.docs;
        final currentUid = FirebaseAuth.instance.currentUser?.uid;

        return Padding(
          padding: const EdgeInsets.only(left: 30, top: 8),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: replies.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final rdoc = replies[i];
              final data = rdoc.data();
              final canDelete = currentUid != null &&
                  (data['uid'] == currentUid ||
                   data['userId'] == currentUid ||
                   data['authorUid'] == currentUid);

              return _ReplyListTile(
                replyId: rdoc.id,
                commentRef: commentRef,
                name: (data['displayName'] ?? 'User').toString(),
                text: (data['text'] ?? '').toString(),
                photoUrl: (data['photoUrl'] ?? '').toString(),
                timestamp: data['createdAt'] as Timestamp?,
                replyingToName: parentUserName,
                canDelete: canDelete,
              );
            },
          ),
        );
      },
    );
  }
}

class _ReplyListTile extends StatelessWidget {
  final String replyId;
  final DocumentReference<Map<String, dynamic>> commentRef;

  final String name;
  final String text;
  final String? photoUrl;
  final Timestamp? timestamp;
  final String replyingToName;
  final bool canDelete;

  const _ReplyListTile({
    required this.replyId,
    required this.commentRef,
    required this.name,
    required this.text,
    this.photoUrl,
    this.timestamp,
    required this.replyingToName,
    this.canDelete = false,
  });

  String _getTimeAgo(Timestamp? ts) {
    if (ts == null) return '';
    return timeago.format(ts.toDate(), locale: 'en_short');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UserAvatar(photoUrl: photoUrl, radius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    const SizedBox(width: 8),
                    Text('@$replyingToName',
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(width: 8),
                    Text(_getTimeAgo(timestamp),
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 11)),
                    const Spacer(),
                    if (canDelete)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded,
                            size: 18, color: Colors.white70),
                        onSelected: (value) async {
                          if (value == 'delete') {
                            try {
                              await commentRef.collection('replies').doc(replyId).delete();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Reply deleted')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Delete failed: $e')),
                              );
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: const [
                                Icon(Icons.delete_outline,
                                    color: _StoryPlayerScreenState.kAccentOrange, size: 20),
                                SizedBox(width: 8),
                                Text('Delete',
                                    style: TextStyle(
                                      color: _StoryPlayerScreenState.kAccentOrange,
                                      fontWeight: FontWeight.w600,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(text,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/* ===================== Reply Input (emoji/phrases) ===================== */

class _ReplyInputModal extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> storyRef;
  final String parentCommentId;
  final String parentUserName;
  final String? currentUserPhotoUrl;

  const _ReplyInputModal({
    required this.storyRef,
    required this.parentCommentId,
    required this.parentUserName,
    this.currentUserPhotoUrl,
  });

  static void show(
    BuildContext context, {
    required DocumentReference<Map<String, dynamic>> storyRef,
    required String parentCommentId,
    required String parentUserName,
    required String? currentUserPhotoUrl,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReplyInputModal(
        storyRef: storyRef,
        parentCommentId: parentCommentId,
        parentUserName: parentUserName,
        currentUserPhotoUrl: currentUserPhotoUrl,
      ),
    );
  }

  @override
  State<_ReplyInputModal> createState() => __ReplyInputModalState();
}

class __ReplyInputModalState extends State<_ReplyInputModal> {
  final TextEditingController _replyCtrl = TextEditingController();
  bool _emojiMode = true;

  Future<Map<String, String?>> _preferredChildDataForUid(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data();

      String? displayName;
      String? photoUrl;

      if (data != null) {
        final child = (data['child'] is Map)
            ? Map<String, dynamic>.from(data['child'] as Map)
            : null;

        final nick = (child?['nickName'] ?? data['childNickname'])?.toString();
        if (nick != null && nick.trim().isNotEmpty) {
          displayName = nick.trim(); // PRIORITIZE NICKNAME
        }

        final p = (child?['photoUrl'] ?? data['profileImageUrl'])?.toString();
        if (p != null && p.isNotEmpty) photoUrl = p;
      }

      displayName ??= FirebaseAuth.instance.currentUser?.displayName
           ?? FirebaseAuth.instance.currentUser?.email
           ?? 'User';

      return {'displayName': displayName, 'photoUrl': photoUrl};
    } catch (_) {
      final u = FirebaseAuth.instance.currentUser;
      return {'displayName': u?.displayName ?? u?.email ?? 'User', 'photoUrl': u?.photoURL};
    }
  }

  Future<void> _postReply() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;

    final settings = await ParentalService.instance.get();
    if (!settings.commentsEnabled) {
      final ok = await gate.requireParentPinOnce(context, reason: 'Post a reply');
      if (!ok) return;
    }

    try {
      final child = await _preferredChildDataForUid(user.uid);
      await widget.storyRef
          .collection('comments')
          .doc(widget.parentCommentId)
          .collection('replies')
          .add({
        'uid': user.uid,
        'displayName': child['displayName'] ?? (user.displayName ?? user.email ?? 'User'),
        'photoUrl': child['photoUrl'], // may be null
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'parentCommentId': widget.parentCommentId,
      });

      _replyCtrl.clear();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reply posted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post reply: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    const Color bg = Colors.black;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Replying to @${widget.parentUserName}',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _UserAvatar(photoUrl: widget.currentUserPhotoUrl, radius: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    readOnly: true,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    minLines: 1,
                    maxLines: 5,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.normal),
                    decoration: InputDecoration(
                      hintText: 'Tap 🙂 or ✍️ below to compose...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SendButton(onPressed: _postReply),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('🙂 Emoji'),
                  selected: _emojiMode,
                  onSelected: (_) => setState(() => _emojiMode = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('✍️ Text'),
                  selected: !_emojiMode,
                  onSelected: (_) => setState(() => _emojiMode = false),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: _emojiMode
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _StoryPlayerScreenState._emojis
                          .map((e) => _ChipPill(
                                label: e,
                                onTap: () => setState(() {
                                  _replyCtrl.text = (_replyCtrl.text + (_replyCtrl.text.isEmpty ? '' : ' ') + e).trimLeft();
                                }),
                              ))
                          .toList(),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _StoryPlayerScreenState._nicePhrases
                          .map((p) => _ChipPill(
                                label: p,
                                onTap: () => setState(() {
                                  _replyCtrl.text = p;
                                }),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== More-in-category strip ===================== */

class _MoreInCategoryStrip extends StatelessWidget {
  final String category;
  final String language;
  final Timestamp before; // show older than this
  final void Function(String storyId) onOpen;

  const _MoreInCategoryStrip({
    required this.category,
    required this.language,
    required this.before,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('stories')
        .where('category', isEqualTo: category)
        .where('createdAt', isLessThan: before)
        .orderBy('createdAt', descending: true)
        .limit(12);

    final lang = language.trim();
    if (lang.isNotEmpty) {
      q = q.where('language', isEqualTo: lang);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: AppLoader(size: 44)),
          );
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();

        // Column list with BIG square thumbnails
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final s = Story.fromFirestore(doc);
            return _MoreStoryTile(
              id: doc.id,
              title: s.title,
              cover: s.coverImageUrl,
              onTap: () => onOpen(doc.id),
            );
          },
        );
      },
    );
  }
}

class _MoreStoryTile extends StatelessWidget {
  final String id;
  final String title;
  final String cover;
  final VoidCallback onTap;

  const _MoreStoryTile({
    required this.id,
    required this.title,
    required this.cover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 110,
                height: 110,
                child: CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.black26),
                  errorWidget: (_, __, ___) => Container(color: Colors.black26),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== Minimal model for typed audio ===================== */

class StoryScriptItem {
  final String type; // 'audio' | 'prompt'
  final String? audioUrl;
  final String? text;
  final int? pauseDurationMs;

  StoryScriptItem({
    required this.type,
    this.audioUrl,
    this.text,
    this.pauseDurationMs,
  });

  factory StoryScriptItem.fromJson(Map<String, dynamic> json) {
    return StoryScriptItem(
      type: (json['type'] ?? '').toString(),
      audioUrl: json['audioUrl']?.toString(),
      text: json['text']?.toString(),
      pauseDurationMs: json['pauseDurationMs'] is int
          ? json['pauseDurationMs'] as int
          : null,
    );
  }
}

class _LangNoBadge extends StatelessWidget {
  final String? language;
  final int? storyNo;
  final double scale;

  const _LangNoBadge({
    required this.language,
    required this.storyNo,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final lc = (language ?? '').trim();
    final no = storyNo;
    if (lc.isEmpty && no == null) return const SizedBox.shrink();

    final langLabel = lc.isEmpty ? '' : lc.toUpperCase();
    final noLabel = (no == null) ? '' : no.toString().padLeft(2, '0');

    final textStyle = TextStyle(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      height: 1.0,
    );

        return Container(
          width: 38 * scale,
          height: 38 * scale,
          padding: EdgeInsets.symmetric(vertical: 6 * scale, horizontal: 4 * scale),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (langLabel.isNotEmpty)
                Text(
                  langLabel,
                  style: textStyle.copyWith(fontSize: 10 * scale),
                  textAlign: TextAlign.center,
                ),
              if (langLabel.isNotEmpty && noLabel.isNotEmpty) SizedBox(height: 2 * scale),
              if (noLabel.isNotEmpty)
                Text(
                  noLabel,
                  style: textStyle.copyWith(fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        );
  }
}