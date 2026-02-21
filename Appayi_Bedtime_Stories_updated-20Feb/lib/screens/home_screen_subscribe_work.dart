
// // lib/screens/home_screen.dart
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:audio_story_app/widgets/background_container.dart';
// import 'package:lottie/lottie.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_storage/firebase_storage.dart';
// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:just_audio/just_audio.dart';
// import 'package:app_links/app_links.dart';
// import 'package:audio_story_app/services/subscription_access_service.dart';
// import 'package:audio_story_app/widgets/premium_subscribe_dialog.dart';

// import 'package:audio_story_app/models/story_model.dart';
// import 'package:audio_story_app/screens/story_player_screen.dart';
// import 'package:audio_story_app/screens/categories_screen.dart';
// import 'package:audio_story_app/screens/rewards_screen.dart';
// import 'package:audio_story_app/screens/downloaded_stories_screen.dart';
// import 'package:audio_story_app/services/offline_story_store.dart';
// import 'package:audio_story_app/utils/language_data.dart';
// import 'package:audio_story_app/widgets/app_loaders.dart';

// /* --------------------------------------------------------------------------
//  * Story badge helpers
//  * --------------------------------------------------------------------------
//  */

// int? _coerceInt(dynamic v) {
//   if (v == null) return null;
//   if (v is int) return v;
//   if (v is num) return v.toInt();
//   if (v is String) {
//     final s = v.trim();
//     if (s.isEmpty) return null;
//     final direct = int.tryParse(s);
//     if (direct != null) return direct;
//     final m = RegExp(r'\d+').firstMatch(s);
//     if (m != null) return int.tryParse(m.group(0)!);
//   }
//   return null;
// }

// int? _storyNoFromData(Map<String, dynamic>? data) {
//   if (data == null) return null;
//   final v = data['storyNo'] ??
//       data['story_no'] ??
//       data['storyNumber'] ??
//       data['story_number'] ??
//       data['number'] ??
//       data['no'];
//   return _coerceInt(v);
// }

// String? _langFromData(Map<String, dynamic>? data, {String? fallback}) {
//   final v = (data?['language'] ?? data?['lang'] ?? fallback)?.toString();
//   if (v == null) return null;
//   final s = v.trim();
//   return s.isEmpty ? null : s;
// }

// class HomeScreen extends StatefulWidget {
//   const HomeScreen({Key? key}) : super(key: key);
//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin<HomeScreen> {
//   StreamSubscription<bool>? _subStatusSub;
//   bool _isSubscribedUser = false;


//   static final Set<String> _hiddenCategoryNames = <String>{
//     'bedtime stories',
//     'science and environmental',
//   };

//   static String _normCat(String s) {
//     return s
//         .toLowerCase()
//         .replaceAll(RegExp(r'\.+$'), '')
//         .replaceAll(RegExp(r'\s+'), ' ')
//         .trim();
//   }

//   static bool _isHiddenCategory({required String key, required String label}) {
//     final nk = _normCat(key);
//     final nl = _normCat(label);
//     return _hiddenCategoryNames.contains(nk) || _hiddenCategoryNames.contains(nl);
//   }

//   static List<Map<String, String>> _visibleCategories(List<dynamic> raw) {
//     final out = <Map<String, String>>[];
//     for (final item in raw) {
//       if (item is Map) {
//         final key = (item['key'] ?? '').toString();
//         final label = (item['label'] ?? '').toString();
//         if (_isHiddenCategory(key: key, label: label)) continue;
//         out.add(<String, String>{'key': key, 'label': label});
//       }
//     }
//     return out;
//   }

//   final User? _currentUser = FirebaseAuth.instance.currentUser;

//   List<String> _selectedLanguages = ['en'];
//   String _activeLanguage = 'en';
//   StreamSubscription? _userSub;
//   Map<String, dynamic> _userData = {};

//   // Deep Links
//   late AppLinks _appLinks;
//   StreamSubscription<Uri>? _linkSubscription;
//   bool _deepLinkNavigating = false;

//   final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>> _streamCache = {};

//   Stream<QuerySnapshot<Map<String, dynamic>>> _cachedStream(
//     String key,
//     Query<Map<String, dynamic>> q,
//   ) {
//     return _streamCache.putIfAbsent(key, () => q.snapshots());
//   }

//   @override
//   bool get wantKeepAlive => true;


//   String _langLabelEn(String code) {
//     switch (code) {
//       case 'en': return 'English';
//       case 'hi': return 'Hindi';
//       case 'ta': return 'Tamil';
//       case 'te': return 'Telugu';
//       case 'ml': return 'Malayalam';
//       case 'kn': return 'Kannada';
//       default: return code.toUpperCase();
//     }
//   }


//   @override
//   void initState() {
//     super.initState();

//     _subStatusSub = SubscriptionAccessService.instance.watchIsSubscribed().listen((v) {
//       if (!mounted) return;
//       setState(() => _isSubscribedUser = v);
//     });

// _userSub = _userStream().listen((data) {
//       if (!mounted) return;
//       final List<String> langs = (data['selectedLanguages'] is List)
//           ? List<String>.from(data['selectedLanguages'] as List)
//           : ['en'];
//       if (langs.isEmpty) langs.add('en');
//       setState(() {
//         _selectedLanguages = langs;
//         _userData = data;
//         if (_activeLanguage.isEmpty || !_selectedLanguages.contains(_activeLanguage)) {
//           _activeLanguage = _selectedLanguages.contains('en') ? 'en' : _selectedLanguages.first;
//         }
//       });
//     });

//     _initDeepLinks();
//   }

//   Future<void> _initDeepLinks() async {
//     _appLinks = AppLinks();
//     try {
//       final Uri? initialLink = await _appLinks.getInitialLink();
//       if (initialLink != null) {
//         _handleDeepLink(initialLink);
//       }
//     } catch (_) {}

//     _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
//       _handleDeepLink(uri);
//     });
//   }

//   void _handleDeepLink(Uri uri) {
//     if (!mounted) return;
//     if (_deepLinkNavigating) return;

//     // Strategy 1: Check for Query Parameter (?storyId=123)
//     final paramId = uri.queryParameters['storyId'];
//     if (paramId != null && paramId.isNotEmpty) {
//       final decodedId = Uri.decodeComponent(paramId);
//       _deepLinkNavigating = true;
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (!mounted) return;
//         Future.delayed(const Duration(milliseconds: 150), () {
//           if (!mounted) return;
//           Navigator.push(context, storyPlayerRoute(decodedId)).whenComplete(() {
//             _deepLinkNavigating = false;
//           });
//         });
//       });
//       return;
//     }

//     // Strategy 2: Path Segment
//     if (uri.pathSegments.contains('story')) {
//       final index = uri.pathSegments.indexOf('story');
//       if (index + 1 < uri.pathSegments.length) {
//         final id = uri.pathSegments[index + 1];
//         if (id.isNotEmpty) {
//           final decodedId = Uri.decodeComponent(id);
//           _deepLinkNavigating = true;
//           WidgetsBinding.instance.addPostFrameCallback((_) {
//             if (!mounted) return;
//             Future.delayed(const Duration(milliseconds: 150), () {
//               if (!mounted) return;
//               Navigator.push(context, storyPlayerRoute(decodedId)).whenComplete(() {
//                 _deepLinkNavigating = false;
//               });
//             });
//           });
//         }
//       }
//     }
//   }

//   @override
//   void dispose() {
//     _subStatusSub?.cancel();
//     _linkSubscription?.cancel();
//     _userSub?.cancel();
//     super.dispose();
//   }

//   Stream<Map<String, dynamic>> _userStream() {
//     final uid = _currentUser?.uid;
//     if (uid == null) return const Stream.empty();
//     return FirebaseFirestore.instance
//         .collection('users')
//         .doc(uid)
//         .snapshots()
//         .map((s) => (s.data() ?? {}));
//   }

//   /* ---------- Query helpers ---------- */

//   Query<Map<String, dynamic>> _applyFilters(
//     Query<Map<String, dynamic>> q, {
//     required String language,
//     String? category,
//   }) {
//     final lang = language.trim().toLowerCase();
//     q = q.where('language', isEqualTo: lang);

//     if (category != null && category.isNotEmpty) {
//       q = q.where('category', isEqualTo: category);
//     }
//     return q;
//   }

//   Query<Map<String, dynamic>> _qNewest({String? category, required String language}) {
//     Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('stories');
//     q = _applyFilters(q, language: language, category: category);
//     return q.orderBy('createdAt', descending: true);
//   }

//   Query<Map<String, dynamic>> _qMostLiked({String? category, required String language}) {
//     Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('stories');
//     q = _applyFilters(q, language: language, category: category);
//     return q.orderBy('likes', descending: true);
//   }

//   Query<Map<String, dynamic>> _qMostViewed({String? category, required String language}) {
//     Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('stories');
//     q = _applyFilters(q, language: language, category: category);
//     return q.orderBy('views', descending: true);
//   }

//   void _openViewAll({
//     required String title,
//     required Query<Map<String, dynamic>> base,
//     required String orderByField,
//   }) {
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (_) => _ViewAllPage(
//           title: title,
//           baseQuery: base,
//           orderByField: orderByField,
//         ),
//       ),
//     );
//   }

//   Route _rewardsRoute() {
//     return PageRouteBuilder(
//       pageBuilder: (context, animation, secondaryAnimation) => const RewardsScreen(),
//       transitionDuration: const Duration(milliseconds: 240),
//       reverseTransitionDuration: const Duration(milliseconds: 200),
//       transitionsBuilder: (context, animation, secondaryAnimation, child) {
//         final curved = CurvedAnimation(
//           parent: animation,
//           curve: Curves.easeOutCubic,
//           reverseCurve: Curves.easeInCubic,
//         );
//         return FadeTransition(
//           opacity: curved,
//           child: SlideTransition(
//             position: Tween<Offset>(
//               begin: const Offset(0.04, 0),
//               end: Offset.zero,
//             ).animate(curved),
//             child: child,
//           ),
//         );
//       },
//     );
//   }


//   Route _downloadsRoute() {
//     return PageRouteBuilder(
//       pageBuilder: (context, animation, secondaryAnimation) =>
//           const DownloadedStoriesScreen(),
//       transitionDuration: const Duration(milliseconds: 240),
//       reverseTransitionDuration: const Duration(milliseconds: 200),
//       transitionsBuilder: (context, animation, secondaryAnimation, child) {
//         final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
//         final offsetTween = Tween<Offset>(
//           begin: const Offset(0.06, 0),
//           end: Offset.zero,
//         ).animate(curved);
//         return FadeTransition(
//           opacity: curved,
//           child: SlideTransition(position: offsetTween, child: child),
//         );
//       },
//     );
//   }

//   Widget _goldTrophyIcon(Color _) {
//     const double size = 26;
//     const gradient = LinearGradient(
//       begin: Alignment.topLeft,
//       end: Alignment.bottomRight,
//       colors: [
//         Color(0xFFFFF3B0),
//         Color(0xFFF2D36B),
//         Color(0xFFD4AF37),
//         Color(0xFFB8860B),
//         Color(0xFF7A5A00),
//       ],
//       stops: [0.0, 0.25, 0.55, 0.8, 1.0],
//     );

//     return Stack(
//       alignment: Alignment.center,
//       children: [
//         Icon(Icons.emoji_events_rounded,
//             size: size, color: Colors.black.withOpacity(0.25)),
//         ShaderMask(
//           shaderCallback: (bounds) => gradient.createShader(bounds),
//           blendMode: BlendMode.srcIn,
//           child: const Icon(Icons.emoji_events_rounded,
//               size: size, color: Colors.white),
//         ),
//       ],
//     );
//   }

// @override
//   Widget build(BuildContext context) {
//     super.build(context);
//     final dark = Theme.of(context).brightness == Brightness.dark;
//     final bg = dark ? Theme.of(context).scaffoldBackgroundColor : Colors.white;
//     final onBg = dark ? Colors.white : Colors.black;
//     final onBg2 = dark ? Colors.white70 : Colors.black54;

//     String greetName = 'Friend';
//     String? avatarUrl;
//     String gender = '';

//     if (_userData.isNotEmpty) {
//       final data = _userData;
//       final child = (data['child'] is Map) ? data['child'] as Map : null;
//       final nick = (child?['nickName'] ?? data['childNickname'])?.toString();
//       final realName = (child?['name'] ?? data['childName'])?.toString();
//       greetName = (nick != null && nick.trim().isNotEmpty)
//           ? nick.trim()
//           : (realName != null && realName.trim().isNotEmpty
//               ? realName.split(' ').first
//               : 'Friend');
//       avatarUrl = (child?['photoUrl'] ?? data['profileImageUrl'])?.toString();
//       gender = (child?['gender'] ?? data['gender'] ?? '').toString();
//     }

//     final g = gender.trim().toLowerCase();
    
//     final Color nameColor = (g == 'male' || g == 'boy')
//         ? const Color(0xFF00C3FF) 
//         : (g == 'female' || g == 'girl')
//             ? const Color(0xFFFF00FF) 
//             : const Color(0xFF9C27B0);

//     final List<String> langButtons =
//         _selectedLanguages.isNotEmpty ? _selectedLanguages : <String>['en'];
//     const double pinnedLangHeaderHeight = 44 + 16; 

//     return AppBackground(
//       animated: true,
//       dimOpacity: 0.08,
//       child: Scaffold(
//       backgroundColor: Colors.transparent,
//       appBar: AppBar(
//         backgroundColor: Colors.transparent,
//         surfaceTintColor: Colors.transparent,
//         scrolledUnderElevation: 0,
//         shadowColor: Colors.transparent,
//         elevation: 0,
//         titleSpacing: 16,
//         title: Row(
//           children: [
//             CircleAvatar(
//               radius: 20,
//               backgroundColor: const Color(0xFF90CAF9),
//               backgroundImage:
//                   (avatarUrl?.isNotEmpty ?? false) ? NetworkImage(avatarUrl!) : null,
//               child: (avatarUrl == null || avatarUrl!.isEmpty)
//                   ? const Icon(Icons.person, color: Colors.white)
//                   : null,
//             ),
//             const SizedBox(width: 12),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text('Welcome', style: TextStyle(color: onBg2, fontSize: 14)),
//                   Text(
//                     greetName,
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis,
//                     style: TextStyle(
//                         color: nameColor,
//                         fontWeight: FontWeight.w900,
//                         fontSize: 22),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//         actions: [
//           IconButton(
//             tooltip: 'Downloads',
//             icon: Icon(Icons.download_for_offline_rounded, color: onBg),
//             onPressed: () => Navigator.of(context).push(_downloadsRoute()),
//           ),

//           IconButton(
//             tooltip: 'Rewards',
//             icon: _goldTrophyIcon(onBg),
//             onPressed: () => Navigator.of(context).push(_rewardsRoute()),
//           ),
          
//           const SizedBox(width: 8),
//         ],
//       ),

//       body: RefreshIndicator(
//         onRefresh: () async => setState(() {}),
//         child: CustomScrollView(
//           physics: const AlwaysScrollableScrollPhysics(),
//           slivers: [
//             const SliverToBoxAdapter(child: SizedBox(height: 10)),

//             SliverPersistentHeader(
//               pinned: true,
//               delegate: _LanguageHeaderDelegate(
//                 height: pinnedLangHeaderHeight,
//                 backgroundColor: bg,
//                 child: Padding(
//                   padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
//                   child: _LanguageButtonsRow(
//                     languages: langButtons,
//                     active: _activeLanguage.isNotEmpty
//                         ? _activeLanguage
//                         : ((_selectedLanguages.contains('en')
//                             ? 'en'
//                             : (_selectedLanguages.isNotEmpty
//                                 ? _selectedLanguages.first
//                                 : 'en'))),
//                     onSelect: (code) => setState(() => _activeLanguage = code),
//                   ),
//                 ),
//               ),
//             ),

//             const SliverToBoxAdapter(child: SizedBox(height: 8)),

//             SliverToBoxAdapter(
//               child: Builder(builder: (context) {
//                 final langCode = (_activeLanguage.isNotEmpty &&
//                         (_selectedLanguages.contains(_activeLanguage)))
//                     ? _activeLanguage
//                     : (_selectedLanguages.contains('en')
//                         ? 'en'
//                         : (_selectedLanguages.isNotEmpty
//                             ? _selectedLanguages.first
//                             : 'en'));
//                 final langName = _langLabelEn(langCode);
//                 final langCategories = _visibleCategories(LanguageData.categoriesByLang[langCode] ?? []);

//                 return Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     if (!_isSubscribedUser) _FreeStoriesRow(langCode: langCode),
//                     _WhatsNewRow(stream: _cachedStream('whatsNew:$langCode', _qNewest(language: langCode).limit(10))),
//                     _CategorySectionCard(
//                       categories: langCategories,
//                       langCode: langCode,
//                       onTapMore: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
//                       onTapCategory: (label, key) => _openViewAll(title: label, base: _qNewest(category: key, language: langCode), orderByField: 'createdAt'),
//                     ),
//                     _SectionCard(
//                       title: 'Popular in $langName',
//                       onMore: () => _openViewAll(title: 'Popular in $langName', base: _qMostLiked(language: langCode), orderByField: 'likes'),
//                       child: _HorizontalStories(stream: _cachedStream('popular:$langCode', _qMostLiked(language: langCode).limit(10))),
//                     ),
//                     _SectionCard(
//                       title: 'Most Viewed in $langName',
//                       onMore: () => _openViewAll(title: 'Most Viewed in $langName', base: _qMostViewed(language: langCode), orderByField: 'views'),
//                       child: _HorizontalStories(stream: _cachedStream('mostViewed:$langCode', _qMostViewed(language: langCode).limit(10))),
//                     ),
//                     const SizedBox(height: 6),
//                     ...langCategories.map((c) {
//                       final label = c['label'] ?? '';
//                       final key = c['key'] ?? '';
//                       return _SectionCard(
//                         title: label,
//                         onMore: () => _openViewAll(title: label, base: _qNewest(category: key, language: langCode), orderByField: 'createdAt'),
//                         child: _HorizontalStories(stream: _cachedStream('cat:$langCode:$key', _qNewest(category: key, language: langCode).limit(10))),
//                       );
//                     }).toList(),
//                   ],
//                 );
//               }),
//             ),
//             SliverToBoxAdapter(
//               child: SizedBox(
//                 height: 24 + MediaQuery.of(context).padding.bottom + 72,
//               ),
//             ),
//           ],
//         ),
//       ),
//     ));
//   }
// }

// /* ===================== Layout blocks ===================== */


// class _LanguageHeaderDelegate extends SliverPersistentHeaderDelegate {
//   final double height;
//   final Color backgroundColor;
//   final Widget child;

//   _LanguageHeaderDelegate({
//     required this.height,
//     required this.backgroundColor,
//     required this.child,
//   });

//   @override
//   double get minExtent => height;

//   @override
//   double get maxExtent => height;

//   @override
//   Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
//     return Container(
//       color: backgroundColor,
//       child: child,
//     );
//   }

//   @override
//   bool shouldRebuild(covariant _LanguageHeaderDelegate oldDelegate) {
//     return height != oldDelegate.height ||
//         backgroundColor != oldDelegate.backgroundColor ||
//         child != oldDelegate.child;
//   }
// }


// class _LanguageButtonsRow extends StatelessWidget {
//   final List<String> languages;
//   final String active;
//   final ValueChanged<String> onSelect;

//   const _LanguageButtonsRow({
//     required this.languages,
//     required this.active,
//     required this.onSelect,
//   });

//   String _labelFor(String code) {
//     switch (code) {
//       case 'en': return 'English';
//       case 'hi': return 'Hindi';
//       case 'ta': return 'Tamil';
//       case 'te': return 'Telugu';
//       case 'ml': return 'Malayalam';
//       case 'kn': return 'Kannada';
//       default: return code.toUpperCase();
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final dark = Theme.of(context).brightness == Brightness.dark;

//     return LayoutBuilder(
//       builder: (context, constraints) {
//         const int maxVisible = 3;
//         const double spacing = 10;
//         final double itemWidth =
//             (constraints.maxWidth - (spacing * (maxVisible - 1))) / maxVisible;

//         final int count = languages.length;
//         final double contentWidth =
//             (count * itemWidth) + (count > 0 ? (count - 1) * spacing : 0);

//         final list = SizedBox(
//           height: 58,
//           child: ListView.separated(
//             scrollDirection: Axis.horizontal,
//             physics: count > maxVisible
//                 ? const BouncingScrollPhysics()
//                 : const NeverScrollableScrollPhysics(),
//             itemCount: count,
//             separatorBuilder: (_, __) => const SizedBox(width: spacing),
//             itemBuilder: (context, index) {
//               final code = languages[index];
//               return SizedBox(
//                 width: itemWidth,
//                 child: _LangButton(
//                   label: _labelFor(code),
//                   selected: code == active,
//                   dark: dark,
//                   onTap: () => onSelect(code),
//                 ),
//               );
//             },
//           ),
//         );

//         if (count <= maxVisible) {
//           return Align(
//             alignment: Alignment.center,
//             child: ConstrainedBox(
//               constraints: BoxConstraints(maxWidth: contentWidth),
//               child: list,
//             ),
//           );
//         }

//         return list;
//       },
//     );
//   }
// }



// class _LangButton extends StatefulWidget {
//   final String label;
//   final bool selected;
//   final bool dark;
//   final VoidCallback onTap;

//   const _LangButton({
//     required this.label,
//     required this.selected,
//     required this.dark,
//     required this.onTap,
//   });

//   @override
//   State<_LangButton> createState() => _LangButtonState();
// }

// class _LangButtonState extends State<_LangButton>
//     with SingleTickerProviderStateMixin {
//   late final AnimationController _controller;
//   bool _pressed = false;

//   @override
//   void initState() {
//     super.initState();
//     _controller = AnimationController(vsync: this);
//   }

//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }

//   void _playPress() {
//     _controller.forward(from: 0);
//   }

//   @override
//   Widget build(BuildContext context) {
//     final fg = widget.dark ? Colors.white : Colors.white;
//     final textStyle = TextStyle(
//       fontSize: 15,
//       fontWeight: widget.selected ? FontWeight.w800 : FontWeight.w700,
//       color: fg,
//     );

//     return GestureDetector(
//       behavior: HitTestBehavior.opaque,
//       onTapDown: (_) {
//         setState(() => _pressed = true);
//         _playPress();
//       },
//       onTapUp: (_) {
//         setState(() => _pressed = false);
//       },
//       onTapCancel: () {
//         setState(() => _pressed = false);
//         _controller.stop();
//       },
//       onTap: () {
//         _playPress();
//         widget.onTap();
//       },
//       child: Opacity(
//         opacity: (widget.selected || _pressed) ? 1.0 : 0.78,
//         child: Stack(
//           alignment: Alignment.center,
//           children: [
//             ClipRRect(
//               borderRadius: BorderRadius.circular(20),
//               child: SizedBox.expand(
//                 child: Lottie.asset(
//                   'assets/lottie/language_button_pressing.json',
//                   controller: _controller,
//                   repeat: false,
//                   fit: BoxFit.fill,
//                   onLoaded: (composition) {
//                     _controller.duration = composition.duration;
//                     if (_controller.value == 0) {
//                       _controller.value = 0;
//                     }
//                   },
//                 ),
//               ),
//             ),

//             if (widget.selected || _pressed)
//               Positioned.fill(
//                 child: IgnorePointer(
//                   child: DecoratedBox(
//                     decoration: BoxDecoration(
//                       borderRadius: BorderRadius.circular(20),
//                       color: Colors.blue.withOpacity(_pressed ? 0.45 : 0.28),
//                     ),
//                   ),
//                 ),
//               ),

//             Positioned.fill(
//               child: IgnorePointer(
//                 child: DecoratedBox(
//                   decoration: BoxDecoration(
//                     borderRadius: BorderRadius.circular(20),
//                     border: Border.all(
//                       color: (widget.selected || _pressed)
//                           ? Colors.blue.withOpacity(0.85)
//                           : Colors.white.withOpacity(0.28),
//                       width: (widget.selected || _pressed) ? 1.6 : 1.1,
//                     ),
//                   ),
//                 ),
//               ),
//             ),

//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 12),
//               child: Text(widget.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }


// int? _coerceIntAny(dynamic v) {
//   if (v == null) return null;
//   if (v is int) return v;
//   if (v is num) return v.toInt();
//   if (v is String) return int.tryParse(v);
//   return null;
// }

// int? _storyShareId(Story story) {
//   try {
//     final v = (story as dynamic).shareId;
//     return _coerceIntAny(v);
//   } catch (_) {
//     return null;
//   }
// }

// String _storyLang(Story story) {
//   final raw = (story.language ?? '').toString();
//   return SubscriptionAccessService.instance.normalizeLanguage(raw);
// }

// class _GridStoryThumb extends StatelessWidget {
//   final Story story;
//   const _GridStoryThumb({required this.story});

//   @override
//   Widget build(BuildContext context) {
//     final dark = Theme.of(context).brightness == Brightness.dark;
//     final card = dark ? Colors.white.withOpacity(0.06) : Colors.white;

//     return InkWell(
//       borderRadius: BorderRadius.circular(22),
//       onTap: () async {
//         final canPlay = await SubscriptionAccessService.instance.canPlayStory(
//           language: _storyLang(story),
//           shareId: _storyShareId(story),
//         );
//         if (!canPlay) {
//           showPremiumSubscribeDialog(context);
//           return;
//         }
//         if (!context.mounted) return;
//         Navigator.push(context, storyPlayerRoute(story.id));
//       },
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(22),
//         child: Container(
//           color: card,
//           child: Stack(
//             fit: StackFit.expand,
//             children: [
//               Positioned.fill(child: _CoverImage(key: ValueKey(story.id), src: story.coverImageUrl, fit: BoxFit.cover)),
//               _DownloadedBadge(storyId: story.id),
//               FutureBuilder<bool>(
//                 future: SubscriptionAccessService.instance.canPlayStory(
//                   language: _storyLang(story),
//                   shareId: _storyShareId(story),
//                 ),
//                 builder: (context, snap) {
//                   final locked = snap.hasData && snap.data == false;
//                   if (!locked) return const SizedBox.shrink();
//                   return Positioned(
//                     top: 10,
//                     right: 10,
//                     child: GestureDetector(
//                       onTap: () => showPremiumSubscribeDialog(context),
//                       child: Container(
//                         padding: const EdgeInsets.all(6),
//                         decoration: BoxDecoration(
//                           color: Colors.black.withOpacity(0.55),
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                         child: const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
//                       ),
//                     ),
//                   );
//                 },
//               ),
//               FutureBuilder<bool>(
//                 future: SubscriptionAccessService.instance.canPlayStory(
//                   language: _storyLang(story),
//                   shareId: _storyShareId(story),
//                 ),
//                 builder: (context, snap) {
//                   final locked = snap.hasData && snap.data == false;
//                   if (!locked) return const SizedBox.shrink();
//                   return Positioned.fill(
//                     child: Container(
//                       color: Colors.black.withOpacity(0.35),
//                       alignment: Alignment.center,
//                       child: GestureDetector(
//                         onTap: () => showPremiumSubscribeDialog(context),
//                         child: Container(
//                           padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
//                           decoration: BoxDecoration(
//                             color: Colors.black.withOpacity(0.55),
//                             borderRadius: BorderRadius.circular(18),
//                             border: Border.all(color: Colors.white.withOpacity(0.25)),
//                           ),
//                           child: const Row(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               Icon(Icons.lock_rounded, color: Colors.white, size: 18),
//                               SizedBox(width: 8),
//                               Text('Locked', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   );
//                 },
//               ),
//               Positioned.fill(
//                 child: DecoratedBox(
//                   decoration: BoxDecoration(
//                     gradient: LinearGradient(
//                       begin: Alignment.bottomCenter,
//                       end: Alignment.topCenter,
//                       colors: [
//                         Colors.black.withOpacity(0.12),
//                         Colors.transparent,
//                       ],
//                     ),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }




// class _SectionCard extends StatelessWidget {
//   final String title;
//   final VoidCallback? onMore;
//   final Widget child;

//   const _SectionCard({required this.title, required this.child, this.onMore});

//   @override
//   Widget build(BuildContext context) {
//     final dark = Theme.of(context).brightness == Brightness.dark;
//     final card =
//         dark ? Colors.white.withOpacity(0.06) : Colors.white;
//     final onBg = dark ? Colors.white : Colors.black;

//     return Container(
//       margin: const EdgeInsets.symmetric(vertical: 8),
//       decoration:
//           BoxDecoration(color: card, borderRadius: BorderRadius.circular(16), border: Theme.of(context).brightness == Brightness.dark ? null : Border.all(color: Colors.black.withOpacity(0.06))),
//       clipBehavior: Clip.antiAlias,
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Padding(
//             padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
//             child: Row(
//               children: [
//                 Expanded(
//                   child: Text(
//                     title,
//                     style: TextStyle(
//                         color: onBg,
//                         fontWeight: FontWeight.w800,
//                         fontSize: 18),
//                   ),
//                 ),
//                 if (onMore != null)
//                   TextButton.icon(
//                     onPressed: onMore,
//                     icon: Text('View All',
//                         style:
//                             TextStyle(fontWeight: FontWeight.w700, color: onBg)),
//                     label: Icon(Icons.chevron_right_rounded, color: onBg),
//                   ),
//               ],
//             ),
//           ),
//           child,
//         ],
//       ),
//     );
//   }
// }

// class _CategorySectionCard extends StatelessWidget {
//   final List<Map<String, String>> categories;
//   final String langCode;
//   final VoidCallback onTapMore;
//   final void Function(String label, String key) onTapCategory;

//   const _CategorySectionCard({
//     required this.categories,
//     required this.langCode,
//     required this.onTapMore,
//     required this.onTapCategory,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final dark = Theme.of(context).brightness == Brightness.dark;
//     final card =
//         dark ? Colors.white.withOpacity(0.06) : Colors.white;
//     final onBg = dark ? Colors.white : Colors.black;

//     const double itemHeight = 60;
//     const double gap = 12.0;

//     return Container(
//       margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
//       decoration:
//           BoxDecoration(color: card, borderRadius: BorderRadius.circular(16), border: Theme.of(context).brightness == Brightness.dark ? null : Border.all(color: Colors.black.withOpacity(0.06))),
//       clipBehavior: Clip.antiAlias,
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Padding(
//             padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
//             child: Row(
//               children: [
//                 Expanded(
//                   child: Text(
//                     'Genre Picks',
//                     style: TextStyle(
//                         color: onBg,
//                         fontWeight: FontWeight.w800,
//                         fontSize: 18),
//                   ),
//                 ),
//                 IconButton(
//                   tooltip: 'All Categories',
//                   onPressed: onTapMore,
//                   icon: const Icon(Icons.chevron_right_rounded, size: 22),
//                   color: Colors.blueAccent,
//                   padding: EdgeInsets.zero,
//                   constraints: const BoxConstraints.tightFor(
//                     width: 32,
//                     height: 32,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           LayoutBuilder(
//             builder: (context, constraints) {
//               final itemWidth = (constraints.maxWidth - gap) / 2;
//               return SizedBox(
//                 height: itemHeight + 34,
//                 child: ListView.separated(
//                   scrollDirection: Axis.horizontal,
//                   physics: const BouncingScrollPhysics(),
//                   padding: EdgeInsets.zero,
//                   itemCount: categories.length,
//                   separatorBuilder: (_, __) => const SizedBox(width: gap),
//                   itemBuilder: (_, i) {
//                     final label = categories[i]['label']!;
//                     final key = categories[i]['key']!;
//                     return SizedBox(
//                       width: itemWidth,
//                       child: _GenreTile(
//                         label: label,
//                         categoryKey: key,
//                         langCode: langCode,
//                         height: itemHeight,
//                         onTap: () => onTapCategory(label, key),
//                       ),
//                     );
//                   },
//                 ),
//               );
//             },
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _GenreTile extends StatelessWidget {
//   final String label;
//   final String categoryKey;
//   final String langCode;
//   final double height;
//   final VoidCallback onTap;

//   const _GenreTile({
//     required this.label,
//     required this.categoryKey,
//     required this.langCode,
//     required this.height,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final titleColor =
//         Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black;

//     final q = FirebaseFirestore.instance
//         .collection('stories')
//         .where('language', isEqualTo: langCode.toLowerCase())
//         .where('category', isEqualTo: categoryKey)
//         .orderBy('createdAt', descending: true)
//         .limit(1);

//     return InkWell(
//       onTap: onTap,
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         crossAxisAlignment: CrossAxisAlignment.center,
//         children: [
//           ClipRRect(
//             borderRadius: BorderRadius.circular(10),
//             child: SizedBox(
//               height: height,
//               width: double.infinity,
//               child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
//                 future: q.get(),
//                 builder: (context, s) {
//                   if (s.hasError) return const Icon(Icons.warning, color: Colors.blue, size: 16);
                  
//                   String? coverUrl;
//                   if (s.hasData && s.data!.docs.isNotEmpty) {
//                     final story = Story.fromFirestore(s.data!.docs.first);
//                     coverUrl = story.coverImageUrl;
//                   }
//                   if (coverUrl == null || coverUrl.isEmpty) {
//                     return Container(color: Colors.black12);
//                   }
//                   return _CoverImage(src: coverUrl, fit: BoxFit.cover);
//                 },
//               ),
//             ),
//           ),
//           const SizedBox(height: 6),
//           SizedBox(
//             width: double.infinity,
//             child: Text(
//               label,
//               maxLines: 2,
//               overflow: TextOverflow.ellipsis,
//               textAlign: TextAlign.center,
//               style: TextStyle(
//                   color: titleColor, fontWeight: FontWeight.w600, fontSize: 13),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _FreeStoriesRow extends StatelessWidget {
//   final String langCode;
//   const _FreeStoriesRow({required this.langCode});

//   String _langName(String code) {
//     switch (code) {
//       case 'en':
//         return 'English';
//       case 'hi':
//         return 'Hindi';
//       case 'ta':
//         return 'Tamil';
//       default:
//         return code.toUpperCase();
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final dark = Theme.of(context).brightness == Brightness.dark;
//     final onBg = dark ? Colors.white : Colors.black;
//     final accent = Colors.orange;

//     return FutureBuilder<Set<int>>(
//       future: SubscriptionAccessService.instance.getFreeShareIdsForLanguage(langCode),
//       builder: (context, snap) {
//         final ids = snap.data ?? const <int>{};
//         final idList = ids.toList()..sort();
//         if (ids.isEmpty) {
//           // Show a small row instead of hiding completely so you can detect config/rules issues.
//           return Padding(
//             padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
//             child: Container(
//               padding: const EdgeInsets.all(14),
//               decoration: BoxDecoration(
//                 color: Colors.orange.withOpacity(0.12),
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(color: Colors.orange.withOpacity(0.25)),
//               ),
//               child: Row(
//                 children: [
//                   const Icon(Icons.info_outline, color: Colors.orange),
//                   const SizedBox(width: 10),
//                   Expanded(
//                     child: Text(
//                       'Free Stories (${_langName(langCode)}) are not available right now. '
//                       'This usually means the app cannot read appConfig/freeAccess due to Firestore rules.',
//                       style: TextStyle(color: onBg.withOpacity(0.85), fontWeight: FontWeight.w600),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           );
//         }

//         final first = idList.take(10).toList();
//         final second = idList.skip(10).take(10).toList();

//         final q1 = FirebaseFirestore.instance.collection('stories').where('shareId', whereIn: first);
//         final q2 = second.isEmpty ? null : FirebaseFirestore.instance.collection('stories').where('shareId', whereIn: second);

//         Widget buildList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
//           final stories = docs.map((d) => Story.fromFirestore(d)).toList();
//           return ListView.separated(
//             padding: const EdgeInsets.symmetric(horizontal: 18),
//             scrollDirection: Axis.horizontal,
//             itemCount: stories.length,
//             separatorBuilder: (_, __) => const SizedBox(width: 12),
//             itemBuilder: (_, i) => _StoryTile(story: stories[i], width: 160, dark: true),
//           );
//         }

//         return Padding(
//           padding: const EdgeInsets.only(bottom: 10),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Padding(
//                 padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
//                 child: Row(
//                   children: [
//                     Expanded(
//                       child: Text(
//                         'Free Stories (${_langName(langCode)})',
//                         style: TextStyle(color: onBg, fontSize: 20, fontWeight: FontWeight.w800),
//                       ),
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//                       decoration: BoxDecoration(
//                         color: accent.withOpacity(0.15),
//                         borderRadius: BorderRadius.circular(14),
//                         border: Border.all(color: accent.withOpacity(0.35)),
//                       ),
//                       child: Text('${ids.length} free', style: TextStyle(color: accent, fontWeight: FontWeight.w800)),
//                     ),
//                   ],
//                 ),
//               ),
//               SizedBox(
//                 height: 220,
//                 child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//                   stream: q1.snapshots(),
//                   builder: (context, s1) {
//                     if (s1.connectionState == ConnectionState.waiting && !s1.hasData) {
//                       return const Center(child: CircularProgressIndicator());
//                     }
//                     final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
//                     if (s1.hasData) docs.addAll(s1.data!.docs);

//                     if (q2 == null) {
//                       if (docs.isEmpty) return const Center(child: Text('No free stories found'));
//                       return buildList(docs);
//                     }

//                     return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//                       stream: q2!.snapshots(),
//                       builder: (context, s2) {
//                         if (s2.connectionState == ConnectionState.waiting && !s2.hasData && docs.isEmpty) {
//                           return const Center(child: CircularProgressIndicator());
//                         }
//                         if (s2.hasData) docs.addAll(s2.data!.docs);
//                         if (docs.isEmpty) return const Center(child: Text('No free stories found'));
//                         return buildList(docs);
//                       },
//                     );
//                   },
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }

// class _WhatsNewRow extends StatelessWidget {
//   final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
//   const _WhatsNewRow({required this.stream});

//   @override
//   Widget build(BuildContext context) {
//     final screenW = MediaQuery.of(context).size.width;
//     final double pageGap = 12;
//     final double pageW = screenW * 0.98;

//     return SizedBox(
//       height: pageW,
//       child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//         stream: stream,
//         builder: (context, snap) {
//           if (snap.hasError) {
//             return const Center(child: Text("Index needed (see log)", style: TextStyle(color: Colors.grey)));
//           }

//           if (!snap.hasData) {
//             return const Center(child: AppLoader());
//           }
//           final docs = snap.data!.docs;
//           if (docs.isEmpty) {
//             return const Center(child: Text('No stories yet'));
//           }

//           final controller = PageController(
//             viewportFraction: pageW / screenW,
//             keepPage: true,
//           );

//           return PageView.builder(
//             controller: controller,
//             itemCount: docs.length,
//             padEnds: true,
//             itemBuilder: (_, i) {
//               final doc = docs[i];
//               final story = Story.fromFirestore(doc);
//               final storyNo = _storyNoFromData(doc.data());
//               final lang = _langFromData(doc.data(), fallback: story.language);

//               return Padding(
//                 padding: EdgeInsets.symmetric(horizontal: pageGap / 2),
//                 child: Center(
//                   child: _WhatsNewCard(
//                     story: story,
//                     size: pageW - pageGap,
//                     storyNoOverride: storyNo,
//                     langOverride: lang,
//                   ),
//                 ),
//               );
//             },
//           );
//         },
//       ),
//     );
//   }
// }

// class _WhatsNewCard extends StatelessWidget {
//   final Story story;
//   final double size;
//   final int? storyNoOverride;
//   final String? langOverride;

//   const _WhatsNewCard({
//     required this.story,
//     required this.size,
//     this.storyNoOverride,
//     this.langOverride,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final labelColor = Colors.white70;

//     final int? effectiveNo = story.storyNo ?? storyNoOverride;
//     final String? effectiveLang =
//         (story.language != null && story.language!.trim().isNotEmpty)
//             ? story.language
//             : langOverride;

//     final String? storyNoLabel = (effectiveNo == null)
//         ? null
//         : effectiveNo.toString().padLeft(2, '0');
//     final String? langLabel = (effectiveLang == null || effectiveLang.trim().isEmpty)
//         ? null
//         : effectiveLang.trim().toUpperCase();

//     return InkWell(
//       onTap: () async {
//         final canPlay = await SubscriptionAccessService.instance.canPlayStory(
//           language: _storyLang(story),
//           shareId: _storyShareId(story),
//         );
//         if (!canPlay) {
//           showPremiumSubscribeDialog(context);
//           return;
//         }
//         if (!context.mounted) return;
//         Navigator.push(context, storyPlayerRoute(story.id));
//       },
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(28),
//         child: Stack(
//           alignment: Alignment.bottomLeft,
//           children: [
//             Positioned.fill(child: _CoverImage(key: ValueKey(story.id), src: story.coverImageUrl)),
//             Positioned(
//               top: 12,
//               right: 12,
//               child: _DownloadedBadge(storyId: story.id),
//             ),
//             Positioned(
//               left: 14,
//               bottom: 66,
//               child: Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//                 decoration: BoxDecoration(
//                   color: Colors.black.withOpacity(0.22),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: Text(
//                   'What’s New ?',
//                   style: TextStyle(color: labelColor, fontSize: 14),
//                 ),
//               ),
//             ),
//             Positioned(
//               left: 16,
//               right: 16,
//               bottom: 16,
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 crossAxisAlignment: CrossAxisAlignment.end,
//                 children: [
//                   if (storyNoLabel != null || langLabel != null)
//                     _LangNoBadge(
//                       lang: langLabel,
//                       number: storyNoLabel,
//                       size: 44,
//                     )
//                   else
//                     const SizedBox(width: 44, height: 44),

//                   GestureDetector(
//                     onTap: () => Navigator.push(
//                       context,
//                       storyPlayerRoute(story.id),
//                     ),
//                     child: Container(
//                       width: 46,
//                       height: 32,
//                       decoration: BoxDecoration(
//                         color: const Color(0xFFFF0000), 
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                       child: const Center(
//                         child: Icon(
//                           Icons.play_arrow_rounded,
//                           size: 22,
//                           color: Colors.white,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
// // ---------------------------------------------------------------------------
// //  _HorizontalStories (Updated to use exact square size)
// // ---------------------------------------------------------------------------
// class _HorizontalStories extends StatelessWidget {
//   final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
//   const _HorizontalStories({required this.stream});

//   @override
//   Widget build(BuildContext context) {
//     final dark = Theme.of(context).brightness == Brightness.dark;

//     // Calculate exact tile size (square) to remove extra whitespace
//     final screenW = MediaQuery.of(context).size.width;
//     final double itemSize = (screenW * 0.44).clamp(150.0, 200.0);

//     return SizedBox(
//       height: itemSize, // Force the scroll container to match the item height (Square)
//       child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//         stream: stream,
//         builder: (context, snap) {
//           if (snap.hasError) {
//             print("Firestore Error: ${snap.error}");
//             return const Center(child: Text("Index needed (see log)", style: TextStyle(color: Colors.grey, fontSize: 10)));
//           }

//           if (!snap.hasData) {
//             return const Center(child: AppLoader());
//           }
//           final docs = snap.data!.docs;
//           if (docs.isEmpty) {
//             return const Center(child: Text('No stories yet'));
//           }
//           return ListView.separated(
//             scrollDirection: Axis.horizontal,
//             padding: EdgeInsets.zero,
//             itemBuilder: (_, i) {
//               final doc = docs[i];
//               final story = Story.fromFirestore(doc);
//               final storyNo = _storyNoFromData(doc.data());
//               final lang = _langFromData(doc.data(), fallback: story.language);
//               return _StoryTile(
//                 story: story,
//                 dark: dark,
//                 storyNoOverride: storyNo,
//                 langOverride: lang,
//                 width: itemSize, // Pass the calculated width
//               );
//             },
//             separatorBuilder: (_, __) => const SizedBox(width: 12),
//             itemCount: docs.length,
//           );
//         },
//       ),
//     );
//   }
// }

// class _StoryTile extends StatelessWidget {
//   final Story story;
//   final bool dark;
//   final int? storyNoOverride;
//   final String? langOverride;
//   final double width;

//   const _StoryTile({
//     required this.story,
//     required this.dark,
//     this.storyNoOverride,
//     this.langOverride,
//     required this.width,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final titleColor = dark ? Colors.white : Colors.black;
//     final captionBg = dark ? Colors.black54 : Colors.white70;
//     final captionFg = dark ? Colors.white : Colors.black;

//     final int? effectiveNo = story.storyNo ?? storyNoOverride;
//     final String? effectiveLang =
//         (story.language != null && story.language!.trim().isNotEmpty)
//             ? story.language
//             : langOverride;

//     final String? storyNoLabel = (effectiveNo == null)
//         ? null
//         : effectiveNo.toString().padLeft(2, '0');
//     final String? langLabel = (effectiveLang == null || effectiveLang.trim().isEmpty)
//         ? null
//         : effectiveLang.trim().toUpperCase();

//     return SizedBox(
//       width: width,
//       child: InkWell(
//         onTap: () => Navigator.push(
//           context,
//           storyPlayerRoute(story.id),
//         ),
//         child: AspectRatio(
//           aspectRatio: 1, // Ensures 1:1 Square
//           child: ClipRRect(
//             borderRadius: BorderRadius.circular(20),
//             child: Stack(
//               children: [
//                 Positioned.fill(
//                     child: _CoverImage(key: ValueKey(story.id), src: story.coverImageUrl)),
//                 _DownloadedBadge(storyId: story.id),
//                 if (storyNoLabel != null || langLabel != null)
//                   Positioned(
//                     bottom: 10,
//                     left: 10,
//                     child: _LangNoBadge(
//                       lang: langLabel,
//                       number: storyNoLabel,
//                       size: 22,
//                     ),
//                   ),
//                 if (story.category?.isNotEmpty ?? false)
//                   Positioned(
//                     bottom: 8,
//                     right: 8,
//                     child: Container(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 6, vertical: 3),
//                       decoration: BoxDecoration(
//                           color: captionBg,
//                           borderRadius: BorderRadius.circular(10)),
//                       child: Text(
//                         story.category!,
//                         style: TextStyle(
//                             color: captionFg,
//                             fontSize: 10,
//                             fontWeight: FontWeight.w600),
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// // ---------------------------------------------------------------------------
// //  View All Page
// // ---------------------------------------------------------------------------
// class _ViewAllPage extends StatefulWidget {
//   final String title;
//   final Query<Map<String, dynamic>> baseQuery;
//   final String orderByField;

//   const _ViewAllPage({
//     required this.title,
//     required this.baseQuery,
//     required this.orderByField,
//   });

//   @override
//   State<_ViewAllPage> createState() => _ViewAllPageState();
// }

// class _ViewAllPageState extends State<_ViewAllPage> {
//   static const int _pageSize = 30;

//   final ScrollController _controller = ScrollController();
//   final List<Story> _stories = <Story>[];

//   QueryDocumentSnapshot<Map<String, dynamic>>? _lastDoc;
//   bool _loading = false;
//   bool _hasMore = true;
//   String? _error;

//   @override
//   void initState() {
//     super.initState();
//     _controller.addListener(_onScroll);
//     _loadInitial();
//   }

//   @override
//   void dispose() {
//     _controller.removeListener(_onScroll);
//     _controller.dispose();
//     super.dispose();
//   }

//   void _onScroll() {
//     if (!_controller.hasClients) return;
//     if (_controller.position.extentAfter < 500) {
//       _loadMore();
//     }
//   }

//   Future<void> _loadInitial() async {
//     setState(() {
//       _stories.clear();
//       _lastDoc = null;
//       _hasMore = true;
//       _loading = false;
//       _error = null;
//     });
//     await _loadMore();
//   }

//   Future<void> _loadMore() async {
//     if (_loading || !_hasMore) return;

//     setState(() {
//       _loading = true;
//       _error = null;
//     });

//     try {
//       Query<Map<String, dynamic>> q = widget.baseQuery.limit(_pageSize);
//       if (_lastDoc != null) {
//         q = q.startAfterDocument(_lastDoc!);
//       }

//       final snap = await q.get();
//       final docs = snap.docs;

//       if (!mounted) return;

//       if (docs.isEmpty) {
//         setState(() {
//           _hasMore = false;
//           _loading = false;
//         });
//         return;
//       }

//       final newStories = docs.map((d) => Story.fromFirestore(d)).toList();

//       setState(() {
//         _stories.addAll(newStories);
//         _lastDoc = docs.last;
//         _hasMore = docs.length == _pageSize;
//         _loading = false;
//       });
//     } catch (e) {
//       if (!mounted) return;
//       setState(() {
//         _loading = false;
//         _error = e.toString();
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final dark = Theme.of(context).brightness == Brightness.dark;
//     final onBg = dark ? Colors.white : Colors.black;

//     return Scaffold(
//       appBar: AppBar(
//         title: Text(widget.title, style: TextStyle(color: onBg)),
//         iconTheme: IconThemeData(color: onBg),
//         backgroundColor: Theme.of(context).scaffoldBackgroundColor,
//         elevation: 0,
//       ),
//       body: RefreshIndicator(
//         onRefresh: _loadInitial,
//         child: _stories.isEmpty && _loading
//             ? const Center(child: AppLoader())
//             : _stories.isEmpty && _error != null
//                 ? ListView(
//                     physics: const AlwaysScrollableScrollPhysics(),
//                     children: [
//                       const SizedBox(height: 120),
//                       Center(
//                         child: Padding(
//                           padding: const EdgeInsets.symmetric(horizontal: 16),
//                           child: Text(
//                             'Failed to load stories.\n$_error',
//                             textAlign: TextAlign.center,
//                             style: TextStyle(color: onBg.withOpacity(0.7)),
//                           ),
//                         ),
//                       ),
//                     ],
//                   )
//                 : GridView.builder(
//                     controller: _controller,
//                     physics: const AlwaysScrollableScrollPhysics(),
//                     padding: const EdgeInsets.all(16),
//                     gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//                       crossAxisCount: 2,
//                       mainAxisSpacing: 12,
//                       crossAxisSpacing: 12,
//                       childAspectRatio: 1,
//                     ),
//                     itemCount: _stories.length + (_hasMore ? 1 : 0),
//                     itemBuilder: (_, i) {
//                       if (i >= _stories.length) {
//                         return const Center(
//                           child: Padding(
//                             padding: EdgeInsets.all(12),
//                             child: AppLoader(size: 34),
//                           ),
//                         );
//                       }
//                       return _GridStoryThumb(story: _stories[i]);
//                     },
//                   ),
//       ),
//     );
//   }
// }

// // ---------------------------------------------------------------------------
// //  Utility Functions
// // ---------------------------------------------------------------------------
// Future<String?> _toHttp(String p) async {
//   if (p.isEmpty) return null;
//   p = p.trim();
//   if (p.startsWith('https://')) return p;
//   if (p.startsWith('http://')) {
//     return 'https://${p.substring('http://'.length)}';
//   }
//   if (p.startsWith('gs://')) {
//     try {
//       final ref = FirebaseStorage.instance.refFromURL(p);
//       return await ref.getDownloadURL();
//     } catch (_) {
//       return null;
//     }
//   }
//   return null;
// }

// Future<String> _getAudioDuration(String? gsUrl) async {
//   if (gsUrl == null || gsUrl.isEmpty) return '00:00';
//   try {
//     final downloadUrl = await _toHttp(gsUrl);
//     if (downloadUrl == null) return '00:00';
//     final player = AudioPlayer();
//     final duration = await player.setUrl(downloadUrl);
//     await player.dispose();
//     if (duration == null) return '00:00';
//     final totalSeconds = duration.inSeconds;
//     final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
//     final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
//     return '$minutes:$seconds';
//   } catch (_) {
//     return '--:--';
//   }
// }

// // ---------------------------------------------------------------------------
// //  Common Widgets
// // ---------------------------------------------------------------------------
// class _CoverImage extends StatefulWidget {
//   final String src;
//   final BoxFit fit;
//   const _CoverImage({super.key, required this.src, this.fit = BoxFit.cover});

//   @override
//   State<_CoverImage> createState() => _CoverImageState();
// }

// class _CoverImageState extends State<_CoverImage>
//     with AutomaticKeepAliveClientMixin<_CoverImage> {
//   String? _resolved;
//   bool _firstPainted = false;

//   @override
//   bool get wantKeepAlive => true;

//   @override
//   void initState() {
//     super.initState();
//     _resolve();
//   }

//   @override
//   void didUpdateWidget(covariant _CoverImage oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     if (oldWidget.src.trim() != widget.src.trim()) {
//       _resolved = null;
//       _firstPainted = false;
//       _resolve();
//     }
//   }

//   Future<void> _resolve() async {
//     final p = widget.src.trim();
//     if (p.isEmpty) return;
//     if (p.startsWith('https://') || p.startsWith('http://')) {
//       setState(() =>
//           _resolved = p.startsWith('http://') ? 'https://${p.substring(7)}' : p);
//       return;
//     }
//     if (p.startsWith('gs://')) {
//       try {
//         final ref = FirebaseStorage.instance.refFromURL(p);
//         final url = await ref.getDownloadURL();
//         if (!mounted) return;
//         setState(() => _resolved = url);
//       } catch (_) {
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     super.build(context);
//     if (_resolved == null) {
//       return Container(color: Colors.black12);
//     }
//     return CachedNetworkImage(
//       key: ValueKey(_resolved),
//       imageUrl: _resolved!,
//       fit: widget.fit,
//       useOldImageOnUrlChange: true,
//       fadeInDuration:
//           _firstPainted ? Duration.zero : const Duration(milliseconds: 120),
//       fadeOutDuration: Duration.zero,
//       placeholderFadeInDuration: Duration.zero,
//       placeholder: (c, _) => Container(color: Colors.transparent),
//       errorWidget: (c, _, __) => const Icon(Icons.broken_image_rounded),
//       imageBuilder: (c, provider) {
//         if (!_firstPainted) {
//           WidgetsBinding.instance.addPostFrameCallback((_) {
//             if (mounted) setState(() => _firstPainted = true);
//           });
//         }
//         return DecoratedBox(
//           decoration:
//               BoxDecoration(image: DecorationImage(image: provider, fit: widget.fit)),
//         );
//       },
//     );
//   }
// }

// // -------------------------
// //  Thumbnail Badges
// // -------------------------

// class _DownloadedBadge extends StatelessWidget {
//   final String storyId;
//   final double size;
//   final EdgeInsets padding;

//   const _DownloadedBadge({
//     required this.storyId,
//     this.size = 26,
//     this.padding = const EdgeInsets.all(0),
//   });

//   @override
//   Widget build(BuildContext context) {
//     return ValueListenableBuilder<Set<String>>(
//       valueListenable: OfflineStoryStore.instance.downloadedStoryIds,
//       builder: (_, ids, __) {
//         final downloaded = ids.contains(storyId);
//         if (!downloaded) return const SizedBox.shrink();
//         return Positioned(
//           top: 10,
//           right: 10,
//           child: Padding(
//             padding: padding,
//             child: Container(
//               width: size,
//               height: size,
//               decoration: BoxDecoration(
//                 color: Colors.black.withOpacity(0.55),
//                 borderRadius: BorderRadius.circular(999),
//               ),
//               child: const Center(
//                 child: Icon(
//                   Icons.download_done_rounded,
//                   size: 16,
//                   color: Colors.white,
//                 ),
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }
// }

// class _LangNoBadge extends StatelessWidget {
//   final String? lang;
//   final String? number;
//   final double size;

//   const _LangNoBadge({this.lang, this.number, this.size = 44});

//   @override
//   Widget build(BuildContext context) {
//     final l = (lang ?? '').trim();
//     final n = (number ?? '').trim();
//     if (l.isEmpty && n.isEmpty) return const SizedBox.shrink();

//     return Container(
//       width: size,
//       height: size,
//       decoration: BoxDecoration(
//         color: Colors.black.withOpacity(0.78),
//         borderRadius: BorderRadius.circular(size / 2),
//         border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
//       ),
//       child: Center(
//         child: Padding(
//           padding: EdgeInsets.all((size * 0.12).clamp(2.0, 6.0)),
//           child: FittedBox(
//             fit: BoxFit.scaleDown,
//             child: (l.isNotEmpty && n.isNotEmpty)
//                 ? Column(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       Text(
//                         l,
//                         style: const TextStyle(
//                           color: Colors.white,
//                           fontWeight: FontWeight.w900,
//                           fontSize: 12,
//                           height: 1.0,
//                         ),
//                       ),
//                       const SizedBox(height: 2),
//                       Text(
//                         n,
//                         style: const TextStyle(
//                           color: Colors.white,
//                           fontWeight: FontWeight.w900,
//                           fontSize: 14,
//                           height: 1.0,
//                         ),
//                       ),
//                     ],
//                   )
//                 : Text(
//                     l.isNotEmpty ? l : n,
//                     style: const TextStyle(
//                       color: Colors.white,
//                       fontWeight: FontWeight.w900,
//                       fontSize: 13,
//                       height: 1.0,
//                     ),
//                   ),
//           ),
//         ),
//       ),
//     );
//   }
// }