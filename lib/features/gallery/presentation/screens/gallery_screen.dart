import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../providers/gallery_providers.dart';
import '../widgets/gallery_grid_item.dart';

class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capturesAsync = ref.watch(galleryNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gallery')),
      body: capturesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) =>
            Center(child: Text('Failed to load gallery: $err')),
        data: (captures) {
          if (captures.isEmpty) {
            return const Center(child: Text('No saved detections yet.'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: captures.length,
            itemBuilder: (context, index) {
              final capture = captures[index];
              return GalleryGridItem(
                capture: capture,
                onTap: () => Navigator.of(context).pushNamed(
                  AppRoutes.captureDetail,
                  arguments: capture,
                ),
              );
            },
          );
        },
      ),
    );
  }
}