# UseDartCouchMixin - Reactive API Examples

This mixin provides PouchDB-like reactive APIs for DartCouchDb, allowing you to create streams that automatically update when data changes.

## useDoc()

Watch a single document for changes:

```dart
// Create a stream that watches a document
final docStream = db.useDoc('user-123');

// Listen to changes
final subscription = docStream.listen((doc) {
  if (doc == null) {
    print('Document deleted or not found');
  } else {
    print('Document updated: ${doc.id} rev ${doc.rev}');
    print('Data: ${doc.unmappedProps}');
  }
});

// Later: cancel the subscription
await subscription.cancel();
```

### Use Cases

- Real-time UI updates when a document changes
- Syncing local state with database state
- Form validation that reflects current saved state
- Live document editors with conflict detection

## useView()

Watch a view for changes:

```dart
// Create a design document with a view
final designDoc = DesignDocument(
  id: '_design/users',
  views: {
    'byAge': ViewData(
      map: '''
        function(doc) {
          if (doc.type === 'user') {
            emit(doc.age, doc.name);
          }
        }
      ''',
    ),
  },
);
await db.put(designDoc);

// Watch the view
final viewStream = db.useView(
  'users/byAge',
  startkey: '18',
  endkey: '65',
  includeDocs: true,
);

await for (final result in viewStream) {
  print('View has ${result.totalRows} total rows');
  for (final row in result.rows) {
    print('  Age ${row.key}: ${row.value} (${row.doc?.id})');
  }
}
```

### Key encoding

All key parameters (`startkey`, `endkey`, `key`, `keys`) are **JSON-encoded
strings**. Compound keys (arrays) must be valid JSON. This makes the call
sites verbose because of the nested quoting:

### Filtering with compound keys (startkey / endkey)

CouchDB views often emit compound (array) keys. To query a range within one
dimension, use `startkey` / `endkey` with CouchDB's collation order, where
the empty object `{}` sorts after all other types and serves as an upper bound.

```dart
// View map function emits [parentId, name]:
//   function(doc) {
//     if (doc.type === 'node') emit([doc.parentId, doc.name], null);
//   }

// Fetch all children of a specific parent node.
// Note how the string interpolation gets clumsy with the JSON quoting:
final parentNodeId = 'folder-abc-123';

final childrenStream = db.useView(
  'mediatree/by_parent',
  includeDocs: true,
  startkey: '["$parentNodeId"]',
  endkey: '["$parentNodeId", {}]',
);

await for (final result in childrenStream) {
  if (result == null) continue;
  for (final row in result.rows) {
    print('Child: ${row.doc?.id}');
  }
}
```

### Filtering by specific keys

The `keys` parameter fetches only rows whose key exactly matches one of the
given values. Each entry is a JSON-encoded string — note the double quoting
for string values:

```dart
// View emits the category as key:
//   function(doc) {
//     if (doc.type === 'item') emit(doc.category, null);
//   }

// Watch only items in "fruits" or "dairy".
// The outer quotes are Dart strings, the inner quotes are JSON:
final stream = db.useView(
  'shop/byCategory',
  keys: ['"fruits"', '"dairy"'],
  includeDocs: true,
);

await for (final result in stream) {
  if (result == null) continue;
  for (final row in result.rows) {
    print('${row.key}: ${row.doc?.id}');
  }
}
```

### Parameters

- `viewPathShort`: Format is "designDoc/viewName"
- `includeDocs`: Include full documents in results
- `attachments`: Include attachments with documents
- `startkey`, `endkey`: Range queries (JSON-encoded strings)
- `key`, `keys`: Specific key queries (JSON-encoded strings)
- `limit`, `skip`: Pagination
- `descending`: Reverse sort order
- `group`, `groupLevel`: Grouping for reduce views
- `reduce`: Whether to use reduce function
- `debounceMs`: Delay before re-querying (default: 300ms)

### Use Cases

- Dashboard widgets that update in real-time
- List views that reflect current database state
- Reporting interfaces with live data
- Search results that update as documents change

## useAllDocs()

Watch multiple specific documents:

```dart
// Watch a set of documents
final docsStream = db.useAllDocs(
  keys: ['doc1', 'doc2', 'doc3'],
  includeDocs: true,
  attachments: false,
);

await for (final result in docsStream) {
  for (final row in result.rows) {
    if (row.value.containsKey('error')) {
      print('${row.id}: Not found');
    } else {
      print('${row.id}: ${row.doc?.rev}');
    }
  }
}
```

### Use Cases

- Shopping cart tracking multiple product documents
- Multi-document forms or wizards
- Related document updates (e.g., user + profile + settings)
- Batch operations with live progress

## Performance Considerations

### Debouncing

All stream functions include debouncing to prevent excessive re-queries:

- `useDoc`: 100ms debounce
- `useView`: 300ms debounce (configurable)
- `useAllDocs`: 200ms debounce (configurable)

### Memory Management

Remember to cancel subscriptions when done:

```dart
final subscription = db.useDoc('my-doc').listen((doc) {
  // Handle updates
});

// In cleanup/dispose:
await subscription.cancel();
```

### Filtering

- `useDoc` only re-queries when the specific document changes
- `useView` re-queries on any document change (views determine relevance)
- `useAllDocs` only re-queries when one of the watched documents changes
- Local documents (`_local/*`) are automatically filtered out

## Integration with Flutter

Perfect for Flutter widgets with `StreamBuilder`:

```dart
class UserProfile extends StatelessWidget {
  final DartCouchDb db;
  final String userId;

  const UserProfile({required this.db, required this.userId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CouchDocumentBase?>(
      stream: db.useDoc(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        }
        
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }
        
        final doc = snapshot.data;
        if (doc == null) {
          return Text('User not found');
        }
        
        return Column(
          children: [
            Text('Name: ${doc.unmappedProps['name']}'),
            Text('Email: ${doc.unmappedProps['email']}'),
            Text('Rev: ${doc.rev}'),
          ],
        );
      },
    );
  }
}
```

## Comparison with PouchDB

This implementation is inspired by [pouchdb-react-hooks](https://github.com/ashsmith/pouchdb-react-hooks):

| Feature | PouchDB (React) | DartCouchDb (Dart/Flutter) |
|---------|-----------------|------------------------|
| Watch document | `useDoc(id)` | `useDoc(id)` |
| Watch view | `useView(name)` | `useView(name)` |
| Watch multiple docs | `useAllDocs({keys})` | `useAllDocs(keys: [...])` |
| Auto-updates | ✅ | ✅ |
| Debouncing | ✅ | ✅ (configurable) |
| Memory cleanup | Auto (React) | Manual (cancel subscription) |

## Error Handling

Streams emit errors when database operations fail:

```dart
final subscription = db.useDoc('my-doc').listen(
  (doc) {
    // Handle updates
  },
  onError: (error) {
    print('Database error: $error');
    // Handle error (network issues, permissions, etc.)
  },
);
```

## Testing

The reactive streams work with both HTTP and local databases:

```dart
// HTTP database
final httpDb = await httpServer.db('mydb');
final stream = httpDb.useDoc('doc1');

// Local database
final localDb = await localServer.db('mydb');
final stream = localDb.useDoc('doc1');
```

Both provide the same reactive API with the same behavior.
