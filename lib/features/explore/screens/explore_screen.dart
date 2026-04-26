import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  static const _languages = [
    _Language('Gujarati', 'ગુજરાતી', true),
    _Language('Hindi', 'हिन्दी', false),
    _Language('Tamil', 'தமிழ்', false),
    _Language('Bengali', 'বাংলা', false),
  ];

  static const _topics = [
    _ExploreTopic(
      title: 'Iran war updates',
      subtitle: 'Global news, Gujarati reactions',
      tag: 'News',
      yaps: 428,
      listeners: '12.4K',
      accent: AppColors.filterRaw,
      samples: [
        'Aa headline samjavo simple Gujarati ma.',
        'Oil prices par India ne su farak padse?',
      ],
    ),
    _ExploreTopic(
      title: 'Ahmedabad traffic memes',
      subtitle: 'SG Highway, BRTS, and pure pain',
      tag: 'Local',
      yaps: 189,
      listeners: '5.8K',
      accent: AppColors.accent,
      samples: [
        'Signal green thay etle pan koi move nathi kartu.',
        'Office late? Blame Pakwan cross road.',
      ],
    ),
    _ExploreTopic(
      title: 'Cricket selection drama',
      subtitle: 'Squad talk with Gujarati spice',
      tag: 'Sports',
      yaps: 312,
      listeners: '9.1K',
      accent: AppColors.filterEcho,
      samples: [
        'Aa player ne bench par kem mukyo?',
        'Final over ma heart attack fixed.',
      ],
    ),
    _ExploreTopic(
      title: 'Viral video court',
      subtitle: 'Gujarati verdicts on internet chaos',
      tag: 'Viral',
      yaps: 254,
      listeners: '7.6K',
      accent: AppColors.filterChipmunk,
      samples: [
        'Aa prank hato ke public nuisance?',
        'Comment section karta yaps vadhare funny chhe.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Explore', style: AppTextStyles.headlineLarge),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () {},
            icon: const Icon(Icons.search_rounded,
                color: AppColors.textSecondary),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const _LanguagePanel(languages: _languages),
          const Gap(18),
          const _SectionTitle(
            title: 'Gujarati right now',
            subtitle: 'Global topics, local voices',
          ),
          const Gap(10),
          const _FeaturedRoom(),
          const Gap(18),
          const _SectionTitle(
            title: 'Rooms',
            subtitle: 'Pick a topic and hear yaps in your language',
          ),
          const Gap(10),
          ...[
            _TopicCard(topic: _topics[0]),
            const Gap(10),
            _TopicCard(topic: _topics[1]),
            const Gap(10),
            _TopicCard(topic: _topics[2]),
            const Gap(10),
            _TopicCard(topic: _topics[3]),
          ],
        ],
      ),
    );
  }
}

class _LanguagePanel extends StatelessWidget {
  final List<_Language> languages;

  const _LanguagePanel({required this.languages});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose your language room', style: AppTextStyles.titleMedium),
        const Gap(10),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: languages.length,
            separatorBuilder: (_, __) => const Gap(8),
            itemBuilder: (_, index) => _LanguageChip(
              language: languages[index],
            ),
          ),
        ),
      ],
    );
  }
}

class _LanguageChip extends StatelessWidget {
  final _Language language;

  const _LanguageChip({required this.language});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: language.selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: language.selected ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Text(
            language.name,
            style: AppTextStyles.labelLarge.copyWith(
              color: language.selected ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const Gap(8),
          Text(
            language.nativeName,
            style: AppTextStyles.labelSmall.copyWith(
              color: language.selected ? Colors.white70 : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedRoom extends StatelessWidget {
  const _FeaturedRoom();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary),
                ),
                child: const Icon(Icons.record_voice_over_rounded,
                    color: AppColors.primary),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gujarati pulse',
                        style: AppTextStyles.headlineMedium),
                    const Gap(2),
                    Text('Meme, politics, cricket, business, bad takes',
                        style: AppTextStyles.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const Gap(14),
          const Row(
            children: [
              _RoomStat(icon: Icons.mic_rounded, label: '1.8K yaps today'),
              Gap(12),
              _RoomStat(icon: Icons.hearing_rounded, label: '42K listeners'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  final _ExploreTopic topic;

  const _TopicCard({required this.topic});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: topic.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: topic.accent.withValues(alpha: 0.5)),
                ),
                child: Icon(Icons.forum_rounded, color: topic.accent, size: 20),
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(topic.title,
                              style: AppTextStyles.titleMedium),
                        ),
                        const Gap(8),
                        _Tag(label: topic.tag),
                      ],
                    ),
                    const Gap(4),
                    Text(topic.subtitle, style: AppTextStyles.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const Gap(12),
          Row(
            children: [
              _RoomStat(
                icon: Icons.mic_rounded,
                label: '${topic.yaps} yaps',
              ),
              const Gap(12),
              _RoomStat(
                icon: Icons.trending_up_rounded,
                label: topic.listeners,
              ),
            ],
          ),
          const Gap(12),
          ...topic.samples.map(
            (sample) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _YapSnippet(text: sample),
            ),
          ),
        ],
      ),
    );
  }
}

class _YapSnippet extends StatelessWidget {
  final String text;

  const _YapSnippet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_outline_rounded,
              color: AppColors.textMuted, size: 18),
          const Gap(8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.headlineMedium),
              const Gap(3),
              Text(subtitle, style: AppTextStyles.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoomStat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RoomStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textMuted, size: 15),
        const Gap(5),
        Text(label, style: AppTextStyles.labelSmall),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;

  const _Tag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: AppTextStyles.labelSmall),
    );
  }
}

class _Language {
  final String name;
  final String nativeName;
  final bool selected;

  const _Language(this.name, this.nativeName, this.selected);
}

class _ExploreTopic {
  final String title;
  final String subtitle;
  final String tag;
  final int yaps;
  final String listeners;
  final Color accent;
  final List<String> samples;

  const _ExploreTopic({
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.yaps,
    required this.listeners,
    required this.accent,
    required this.samples,
  });
}
