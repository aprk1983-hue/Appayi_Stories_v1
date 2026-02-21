import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_story_app/services/app_audio_service.dart';
import 'package:audio_story_app/widgets/parent_gate.dart' as gate;
import 'story_player_screen.dart' show StoryPlayerScreen, isStoryPlayerOnTop, storyPlayerRoute;
import 'home_screen.dart';
import 'search_screen.dart';
import 'categories_screen.dart';
import 'playlists_screen.dart';
import 'profile_screen.dart';

// Controls whether the mini player is visible (dismissed via the X button).
final ValueNotifier<bool> miniPlayerVisible = ValueNotifier<bool>(true);

class MainTabs extends StatefulWidget {
  const MainTabs({super.key});
  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  bool _profilePinBusy = false;

  StreamSubscription<PlaybackState>? _playbackSub;
  AudioProcessingState _lastProcessingState = AudioProcessingState.idle;

  int _index = 0;
  
  final Color _neumorphicBase = Colors.black; 
  final Color _accentColor = Colors.orange; 
  final Color _inactiveColor = Colors.white54;

  final _pages = const [
    HomeScreen(),
    SearchScreen(),
    CategoriesScreen(),
    PlaylistsScreen(),
    ProfileScreen(),
  ];

  final List<Map<String, dynamic>> _navItems = [
    {'icon': Icons.home_rounded, 'label': 'Home'},
    {'icon': Icons.search_rounded, 'label': 'Search'},
    {'icon': Icons.grid_view_rounded, 'label': 'Category'},
    {'icon': Icons.playlist_play_rounded, 'label': 'PlayLists'},
    {'icon': Icons.person_rounded, 'label': 'Profile'},
  ];

  @override
  void initState() {
    super.initState();
    _playbackSub = AppAudioService.handler.playbackState.listen((state) {
      final proc = state.processingState;
      // If playback becomes active again (idle -> non-idle) after user dismissed the mini player, show it again.
      if (_lastProcessingState == AudioProcessingState.idle &&
          proc != AudioProcessingState.idle &&
          !miniPlayerVisible.value) {
        miniPlayerVisible.value = true;
      }
      _lastProcessingState = proc;
    });
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    super.dispose();
  }

  void _onNavItemSelected(int i) {
    // Always gate the Profile tab (index 4) with Parent PIN.
    if (i == 4 && _index != 4) {
      _openProfileWithPin();
      return;
    }
    setState(() => _index = i);
  }

  Future<void> _openProfileWithPin() async {
    if (_profilePinBusy) return;
    _profilePinBusy = true;
    try {
      final ok = await gate.requireParentPin(
        context,
        reason: 'Enter Parent PIN to open Profile',
      );
      if (!ok) return;
      if (!mounted) return;
      setState(() => _index = 4);
    } finally {
      _profilePinBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent, 
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _pages),

          ValueListenableBuilder<bool>(
            valueListenable: isStoryPlayerOnTop,
            builder: (context, onTop, _) {
              if (onTop || _index == 4) return const SizedBox.shrink();
              return const _MiniPlayerOverlay();
            },
          ),
        ],
      ),
      
      bottomNavigationBar: _IPhoneBottomBar(
        selectedIndex: _index,
        onItemSelected: _onNavItemSelected,
        items: _navItems,
        activeColor: const Color(0xFF007AFF), // iOS system blue
        inactiveColor: const Color(0xFF8E8E93),
      ),
    );
  }
}

class _NeumorphicBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final List<Map<String, dynamic>> items;
  final Color baseColor;
  final Color accentColor;
  final Color inactiveColor;

  const _NeumorphicBottomBar({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.items,
    required this.baseColor,
    required this.accentColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              offset: const Offset(4, 4),
              blurRadius: 10,
            ),
            const BoxShadow(
              color: Colors.white10,
              offset: Offset(-2, -2),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (i) {
            final bool isSelected = i == selectedIndex;
            return Expanded(
              child: _NeumorphicTabItem(
                icon: items[i]['icon'] as IconData,
                label: items[i]['label'] as String,
                isSelected: isSelected,
                onTap: () => onItemSelected(i),
                baseColor: baseColor,
                accentColor: accentColor,
                inactiveColor: inactiveColor,
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _IPhoneBottomBar extends StatelessWidget {
  const _IPhoneBottomBar({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.items,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final List<Map<String, dynamic>> items;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final barHeight = 64.0 + bottomPad;

    // iOS-style translucent background (looks good on dark or light content)
    final bg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1C1C1E).withOpacity(0.72)
        : Colors.white;

    final topBorder = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withOpacity(0.10)
        : Colors.black.withOpacity(0.08);

    return SizedBox(
      height: barHeight,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
        ),
        child: Container(
            decoration: BoxDecoration(
              color: bg,
              border: Border(top: BorderSide(color: topBorder, width: 1)),
            ),
            padding: EdgeInsets.only(bottom: bottomPad),
            child: Row(
              children: List.generate(items.length, (i) {
                final isSelected = i == selectedIndex;
                final icon = items[i]['icon'] as IconData;
                final label = (items[i]['label'] as String);

                return Expanded(
                  child: _IPhoneTabItem(
                    icon: icon,
                    label: label,
                    selected: isSelected,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: () => onItemSelected(i),
                  ),
                );
              }),
            ),
          ),
      ),
    );
  }
}

class _IPhoneTabItem extends StatefulWidget {
  const _IPhoneTabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  State<_IPhoneTabItem> createState() => _IPhoneTabItemState();
}

class _IPhoneTabItemState extends State<_IPhoneTabItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? widget.activeColor : widget.inactiveColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _pressed ? 0.95 : 1.0,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 24, color: color),
              const SizedBox(height: 4),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _NeumorphicTabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color baseColor;
  final Color accentColor;
  final Color inactiveColor;

  const _NeumorphicTabItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.baseColor,
    required this.accentColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final double buttonSize = isSelected ? 48.0 : 40.0;
    final double iconSize = isSelected ? 28.0 : 24.0;
    final Color itemColor = isSelected ? accentColor : inactiveColor;
    final double shadowDepth = buttonSize * 0.15;

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: baseColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    offset: Offset(shadowDepth, shadowDepth),
                    blurRadius: shadowDepth * 2,
                  ),
                  BoxShadow(
                    color: Colors.white12,
                    offset: Offset(-shadowDepth / 2, -shadowDepth / 2),
                    blurRadius: shadowDepth,
                  ),
                  BoxShadow(
                    color: accentColor.withOpacity(isSelected ? 0.4 : 0.1),
                    blurRadius: shadowDepth * 3,
                    spreadRadius: -shadowDepth * 0.5,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: itemColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: itemColor,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------------
// UPDATED MINI PLAYER: BLUEISH TINT, NO TEXT, NAV BUTTONS + EXIT
// ----------------------------------------------------------------------------------

class _MiniPlayerOverlay extends StatelessWidget {
  const _MiniPlayerOverlay();

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final bottomBarHeight = 64.0 + bottomPad; // matches _IPhoneBottomBar
    final bottomOffset = bottomBarHeight + 12.0;

    return Positioned(
      left: 12,
      right: 12,
      bottom: bottomOffset,
      child: StreamBuilder<MediaItem?>(
        stream: AppAudioService.handler.mediaItem,
        builder: (context, snap) {
          final item = snap.data;
          final storyId = (item?.extras?['storyId'] ?? item?.id)?.toString();
          final art = item?.artUri?.toString() ?? '';
          final prevId = item?.extras?['prevStoryId']?.toString();
          final nextId = item?.extras?['nextStoryId']?.toString();

          return StreamBuilder<PlaybackState>(
            stream: AppAudioService.handler.playbackState,
            builder: (context, stateSnap) {
              final state = stateSnap.data;
              final playing = state?.playing ?? false;
              final processing = state?.processingState ?? AudioProcessingState.idle;
              final hasActive = processing != AudioProcessingState.idle;

              return ValueListenableBuilder<bool>(
                valueListenable: miniPlayerVisible,
                builder: (context, visible, _) {
                  final shouldShow = visible &&
                      hasActive &&
                      storyId != null &&
                      storyId.isNotEmpty;

                  final Widget child = shouldShow
                      ? _MiniPlayerCard(
                          key: ValueKey(storyId),
                          storyId: storyId!,
                          artUrl: art,
                          playing: playing,
                          prevId: prevId,
                          nextId: nextId,
                          onClose: () async {
                            // Hide immediately to avoid any visual flash, then stop audio.
                            miniPlayerVisible.value = false;
                            await AppAudioService.handler.stop();
                          },
                        )
                      : const SizedBox(key: ValueKey('mini_empty'));

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) {
                      final offsetTween = Tween<Offset>(
                        begin: const Offset(0, 0.12),
                        end: Offset.zero,
                      ).animate(anim);
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(position: offsetTween, child: child),
                      );
                    },
                    child: child,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _MiniPlayerCard extends StatelessWidget {
  const _MiniPlayerCard({
    super.key,
    required this.storyId,
    required this.artUrl,
    required this.playing,
    required this.prevId,
    required this.nextId,
    required this.onClose,
  });

  final String storyId;
  final String artUrl;
  final bool playing;
  final String? prevId;
  final String? nextId;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          storyPlayerRoute(storyId),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1B2A).withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF4FC3F7).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: _ArtThumb(url: artUrl),
                  ),
                ),
                const Spacer(),

                IconButton(
                  onPressed: (prevId != null && prevId!.isNotEmpty)
                      ? () => Navigator.of(context).push(
                            storyPlayerRoute(prevId!),
                          )
                      : null,
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    color: (prevId != null && prevId!.isNotEmpty) ? Colors.white : Colors.white24,
                    size: 28,
                  ),
                ),

                IconButton(
                  onPressed: () => playing
                      ? AppAudioService.handler.pause()
                      : AppAudioService.handler.play(),
                  icon: Icon(
                    playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded,
                    color: const Color(0xFF4FC3F7),
                    size: 44,
                  ),
                ),

                IconButton(
                  onPressed: (nextId != null && nextId!.isNotEmpty)
                      ? () => Navigator.of(context).push(
                            storyPlayerRoute(nextId!),
                          )
                      : null,
                  icon: Icon(
                    Icons.skip_next_rounded,
                    color: (nextId != null && nextId!.isNotEmpty) ? Colors.white : Colors.white24,
                    size: 28,
                  ),
                ),

                const Spacer(),

                IconButton(
                  onPressed: () async => await onClose(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtThumb extends StatelessWidget {
  const _ArtThumb({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: Colors.white10),
        child: Icon(Icons.music_note, color: Colors.white38),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const DecoratedBox(
          decoration: BoxDecoration(color: Colors.white10),
          child: Icon(Icons.music_note, color: Colors.white38),
        );
      },
      errorBuilder: (_, __, ___) {
        return const DecoratedBox(
          decoration: BoxDecoration(color: Colors.white10),
          child: Icon(Icons.broken_image, color: Colors.white38),
        );
      },
    );
  }
}


// ---------------------------------------------------------------------------
// Smooth tab switching (keeps tab state, avoids “flash”)
// ---------------------------------------------------------------------------
class _FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _FadeIndexedStack({
    required this.index,
    required this.children,
  });

  @override
  State<_FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<_FadeIndexedStack> {
  int _current = 0;
  int _previous = 0;
  bool _transitioning = false;
  Timer? _t;

  static const _dur = Duration(milliseconds: 170);

  @override
  void initState() {
    super.initState();
    _current = widget.index;
    _previous = widget.index;
  }

  @override
  void didUpdateWidget(covariant _FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != _current) {
      _previous = _current;
      _current = widget.index;
      _transitioning = true;
      _t?.cancel();
      _t = Timer(_dur, () {
        if (mounted) setState(() => _transitioning = false);
      });
      setState(() {}); // start the animation immediately
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: List.generate(widget.children.length, (i) {
        final show = _transitioning ? (i == _current || i == _previous) : (i == _current);
        final opacity = (i == _current) ? 1.0 : 0.0;

        return Positioned.fill(
          child: Offstage(
            // Offstage keeps state alive but avoids painting.
            offstage: !show,
            child: IgnorePointer(
              ignoring: i != _current,
              child: AnimatedOpacity(
                opacity: opacity,
                duration: _dur,
                curve: Curves.easeOut,
                child: TickerMode(
                  enabled: i == _current,
                  child: widget.children[i],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
