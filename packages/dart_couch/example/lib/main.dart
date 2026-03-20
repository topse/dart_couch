// All imports must be at the top
import 'dart:async';
import 'dart:convert';
import 'package:dart_couch/dart_couch.dart';
import 'package:dart_couch_widgets/dart_couch_widgets.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:path/path.dart' as p;

import 'category_dropdown.dart';
import 'current_category_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'einkaufslist_item.dart';
import 'einkaufsliste_migration.dart';
import 'new_item_dialog.dart';
import 'item_list.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartCouchDb.ensureInitialized();
  EinkaufslistItemMapper.ensureInitialized();
  EinkaufslistCategoryMapper.ensureInitialized();

  Logger.root.level = Level.FINEST; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    LineSplitter ls = LineSplitter();
    for (final line in ls.convert(record.message)) {
      // Schedule the logging asynchronously to avoid re-entrancy issues
      scheduleMicrotask(() {
        // ignore: avoid_print
        print(
          '${record.loggerName} ${record.level.name}: ${record.time}: $line',
        );
      });
    }
  });

  OfflineFirstServer server = OfflineFirstServer(
    migration: EinkaufslisteMigration(),
  );
  di.registerSingleton<OfflineFirstServer>(server);

  di.registerSingleton(CurrentCategoryProvider());

  SharedPreferencesWithCache prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(
      // When an allowlist is included, any keys that aren't included cannot be used.
      allowList: <String>{'last_credentials'},
    ),
  );
  di.registerSingleton<SharedPreferencesWithCache>(prefs);

  WidgetsBinding.instance.addObserver(
    OfflineFirstServerLifecycleObserver(server: server),
  );

  runApp(const MyApp());
}

Future<String> _getLocalFilePath() async {
  if (kIsWeb) {
    return 'dart_couch_web';
  }
  final dir = await getApplicationSupportDirectory();
  return p.join(dir.path, 'dart_couch');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _getLocalFilePath(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final server = di<OfflineFirstServer>();
        final localFilePath = snapshot.data!;
        return MaterialApp(
          title: 'Einkaufsliste',
          theme: ThemeData.light(useMaterial3: true),
          darkTheme: ThemeData.dark(useMaterial3: true),
          themeMode: ThemeMode.system,
          home: DcValueListenableBuilder<OfflineFirstServerState>(
            valueListenable: server.state,
            builder: (context, connectionState, _) {
              return DbStateProxyWidget(
                server: server,
                localFilePath: localFilePath,
                databaseFileNamePrefix: 'einkaufsliste',
                credentialsManager: MyCredentialsManager(),
                onLogin: () async {
                  final db =
                      await server.db(
                            DartCouchDb.usernameToDbName(server.username!),
                          )
                          as OfflineFirstDb?;
                  if (db != null) {
                    di.registerSingleton<OfflineFirstDb>(db);
                  } else {
                    di.unregister<OfflineFirstDb>();
                  }
                },
                child: ReplicationStateProxyWidget(
                  server: di<OfflineFirstServer>(),
                  waitForUsersDatabase: true,
                  progressMessage: 'Synchronizing your shopping list...',
                  keepScreenOn: true,
                  child: MyHomePage(),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final server = di<OfflineFirstServer>();
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final server = di<OfflineFirstServer>();
          final db = await server.db(
            DartCouchDb.usernameToDbName(server.username!),
          );
          if (db == null) return;

          if (context.mounted == false) return;

          final newItem = await showDialog<EinkaufslistItem?>(
            context: context,
            builder: (context) => NewItemDialogFixed(db: db),
          );

          if (newItem != null) {
            await db.post(newItem);
          }
        },
        child: const Icon(Icons.add),
      ),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 16),
            CategoryDropdown(server: server),
            const Spacer(),
            OfflineFirstServerStateWidget(
              server: server,
              db: di<OfflineFirstDb>(),
              showPercentage: false,
            ),
          ],
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                final server = di<OfflineFirstServer>();
                server.logout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.deepPurple),
              child: Text(
                'Einkaufsliste',
                style: TextStyle(color: Colors.white),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('App Version'),
              subtitle: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Loading...');
                  } else if (snapshot.hasError) {
                    return const Text('Error');
                  } else {
                    return Text(snapshot.data?.version ?? 'Unknown');
                  }
                },
              ),
            ),
          ],
        ),
      ),
      body: ItemList(),
    );
  }
}

class MyCredentialsManager extends CredentialsManagerBase {
  static const String _keyName = 'last_credentials';

  @override
  LoginCredentials? getCredentials() {
    try {
      final lastCredentials = di<SharedPreferencesWithCache>().getString(
        _keyName,
      );
      if (lastCredentials != null) {
        return LoginCredentials.fromJson(jsonDecode(lastCredentials));
      }
    } catch (_) {}
    return null;
  }

  @override
  void saveCredentials(LoginCredentials? credentials) {
    if (credentials == null) {
      di<SharedPreferencesWithCache>().remove(_keyName);
    } else {
      di<SharedPreferencesWithCache>().setString(
        _keyName,
        jsonEncode(credentials.toJson()),
      );
    }
  }
}
