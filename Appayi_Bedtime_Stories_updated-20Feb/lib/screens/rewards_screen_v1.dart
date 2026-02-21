// lib/screens/rewards_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audio_story_app/models/story_model.dart'; 

// --- This defines your Badges ---
class Badge {
  final String id;
  final String name;
  final IconData icon;
  final String description;
  Badge({required this.id, required this.name, required this.icon, required this.description});
  
  // --- HERE ARE ALL YOUR NEW BADGES ---
  static final Map<String, Badge> allBadges = {
    // Listening Milestones (Early)
    'listened_1': Badge(
      id: 'listened_1',
      name: 'First Listen!',
      icon: Icons.flag_rounded,
      description: "You listened to your very first story!",
    ),
    'listened_5': Badge(
      id: 'listened_5',
      name: 'Listener',
      icon: Icons.hearing_rounded,
      description: "You've listened to 5 stories!",
    ),
    'listened_10': Badge(
      id: 'listened_10',
      name: 'Story Fan',
      icon: Icons.star_rounded,
      description: "You've listened to 10 stories!",
    ),
     'listened_15': Badge(
      id: 'listened_15',
      name: 'Avid Reader',
      icon: Icons.headphones_rounded,
      description: "You've listened to 15 stories!",
    ),
    'listened_20': Badge(
      id: 'listened_20',
      name: 'Bookworm',
      icon: Icons.auto_stories_rounded,
      description: "You've listened to 20 stories!",
    ),
    
    // Listening Milestones (Advanced)
    'listened_50': Badge(
      id: 'listened_50',
      name: 'Bronze Star',
      icon: Icons.looks_5_rounded,
      description: "Wow! 50 stories listened to!",
    ),
    'listened_100': Badge(
      id: 'listened_100',
      name: 'Silver Star',
      icon: Icons.military_tech_rounded,
      description: "Incredible! 100 stories!",
    ),
    'listened_150': Badge(
      id: 'listened_150',
      name: 'Gold Star',
      icon: Icons.emoji_events_rounded,
      description: "Amazing! 150 stories!",
    ),
    'listened_200': Badge(
      id: 'listened_200',
      name: 'Platinum Star',
      icon: Icons.shield_rounded,
      description: "A true champion! 200 stories!",
    ),
    'listened_250': Badge(
      id: 'listened_250',
      name: 'Epic Listener',
      icon: Icons.local_fire_department_rounded,
      description: "You're on fire! 250 stories!",
    ),
    'listened_300': Badge(
      id: 'listened_300',
      name: 'Master Listener',
      icon: Icons.workspace_premium_rounded,
      description: "Master level! 300 stories!",
    ),
     'listened_350': Badge(
      id: 'listened_350',
      name: 'Grand Master',
      icon: Icons.auto_awesome_rounded,
      description: "Truly grand! 350 stories!",
    ),
    'listened_400': Badge(
      id: 'listened_400',
      name: 'Story Sage',
      icon: Icons.self_improvement_rounded,
      description: "So wise! 400 stories!",
    ),
    'listened_450': Badge(
      id: 'listened_450',
      name: 'Story Legend',
      icon: Icons.whatshot_rounded,
      description: "Legendary! 450 stories!",
    ),
    'listened_500': Badge(
      id: 'listened_500',
      name: 'Story Hero',
      icon: Icons.workspace_premium_rounded,
      description: "You're our hero! 500 stories!",
    ),

    // Collection Badges
    'gem_collector_10': Badge(
      id: 'gem_collector_10',
      name: 'Gem Collector',
      icon: Icons.diamond_rounded,
      description: "You collected 10 new story gems!",
    ),
    'explorer_3': Badge(
      id: 'explorer_3',
      name: 'Explorer',
      icon: Icons.explore_rounded,
      description: "You listened to stories from 3 different categories!",
    ),
  };
}


class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  List<String> _unlockedBadgeIds = [];
  List<String> _unlockedGemIds = []; // Renamed from sticker
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRewards();
  }
  
  Future<void> _loadRewards() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    
    final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = snap.data() ?? {};
    
    final badges = (data['unlockedBadges'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    final gems = (data['unlockedGems'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    
    if (mounted) {
      setState(() {
        _unlockedBadgeIds = badges;
        _unlockedGemIds = gems;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Rewards'),
        // --- THIS IS THE NEW BUTTON ---
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'How this works',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _HowItWorksPage()),
              );
            },
          ),
        ],
        // --- END OF NEW BUTTON ---
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orange,
          unselectedLabelColor: isDark ? Colors.white70 : Colors.black54,
          indicatorColor: Colors.orange,
          tabs: const [
            Tab(text: 'Badges', icon: Icon(Icons.military_tech_rounded)),
            Tab(text: 'Gem Collection', icon: Icon(Icons.diamond_outlined)),
          ],
        ),
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: Colors.orange))
        : TabBarView(
            controller: _tabController,
            children: [
              _buildBadgesGrid(),
              _buildGemGrid(),
            ],
          ),
    );
  }

  Widget _buildBadgesGrid() {
    final allBadges = Badge.allBadges.values.toList();
    
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: allBadges.length,
      itemBuilder: (context, index) {
        final badge = allBadges[index];
        final bool isUnlocked = _unlockedBadgeIds.contains(badge.id);
        
        return _BadgeIcon(badge: badge, isUnlocked: isUnlocked);
      },
    );
  }

  Widget _buildGemGrid() {
    if (_unlockedGemIds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            "Listen to new stories to collect gems!", 
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        )
      );
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, // 4 columns
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _unlockedGemIds.length,
      itemBuilder: (context, index) {
        // Just show a gem icon for every item in the list
        return Container(
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Icon(Icons.diamond_rounded, color: Colors.orange, size: 40),
          ),
        );
      },
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  final Badge badge;
  final bool isUnlocked;
  
  const _BadgeIcon({required this.badge, required this.isUnlocked});

  @override
  Widget build(BuildContext context) {
    final color = isUnlocked ? Colors.orange : Colors.grey.withOpacity(0.3);
    final iconColor = isUnlocked ? Colors.white : Colors.grey.withOpacity(0.7);

    return Opacity(
      opacity: isUnlocked ? 1.0 : 0.5,
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(isUnlocked ? badge.description : "Keep listening to unlock!"))
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: color.withOpacity(0.5), width: 4),
              ),
              child: Icon(badge.icon, color: iconColor, size: 40),
            ),
            const SizedBox(height: 8),
            Text(
              badge.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// --- ADDED THIS NEW PAGE WIDGET AT THE BOTTOM ---

class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allBadges = Badge.allBadges.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('How Rewards Work'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: Gems
          Text(
            'How to Earn Gems',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withOpacity(0.3))
            ),
            padding: const EdgeInsets.all(16),
            child: ListTile(
              leading: const Icon(Icons.diamond_rounded, color: Colors.orange, size: 40),
              title: const Text('Collect New Gems', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('You earn one new Gem for every NEW story you listen to for the first time. Fill up your collection!'),
            ),
          ),
          
          const SizedBox(height: 24),

          // Section 2: Badges
          Text(
            'How to Earn Badges',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          const SizedBox(height: 12),
          
          // Use a ListView to show all badge rules
          ListView.separated(
            shrinkWrap: true, // Important inside another ListView
            physics: const NeverScrollableScrollPhysics(), // Important
            itemCount: allBadges.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final badge = allBadges[index];
              return Container(
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.withOpacity(0.3))
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(badge.icon, color: Colors.orange, size: 40),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(badge.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(badge.description, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}