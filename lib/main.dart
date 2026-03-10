import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:githubinsights/data/models/collaborator.dart';
import 'package:githubinsights/data/models/commit.dart';
import 'package:githubinsights/data/models/hive_model.dart';
import 'package:githubinsights/data/models/repository_collaborators.dart';
import 'package:githubinsights/data/models/repository_commits.dart';
import 'package:githubinsights/firebase_options.dart';
import 'package:githubinsights/riverpod/auth_provider.dart';
import 'package:githubinsights/riverpod/router.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check if Firebase is already initialized to prevent duplicate app error
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions
            .currentPlatform); //flutterfire config (firebase_options.dart)
  }
  await Hive.initFlutter();

  Hive.registerAdapter(RepoAdapter());
  Hive.registerAdapter(OwnerAdapter());
  Hive.registerAdapter(PermissionsAdapter());
  Hive.registerAdapter(CollaboratorAdapter());
  Hive.registerAdapter(RepositoryCollaboratorsAdapter());
  Hive.registerAdapter(CommitAdapter());
  Hive.registerAdapter(RepositoryCommitsAdapter());
  Hive.registerAdapter(CommitStatsAdapter());
  Hive.registerAdapter(CommitFileAdapter());

  // Hive.deleteBoxFromDisk('gitReposBox');
  // Hive.deleteBoxFromDisk('repository_collaborators_box');
  await Hive.openBox<Repo>('gitReposBox');
  await Hive.openBox<RepositoryCollaborators>('repository_collaborators_box');
  await Hive.openBox<RepositoryCommits>('gitCommitsBox');

  runApp(const ProviderScope(child: MainApp()));
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(authProvider).checkAuthStatus();

    return MaterialApp.router(
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
