import 'package:test/test.dart';
import 'package:dart_couch/dart_couch.dart';

void main() {
  group('Username to DB name conversion', () {
    test('converts simple username to db name', () {
      expect(
        DartCouchDb.usernameToDbName('alice'),
        equals('userdb-616c696365'),
      );
    });

    test('converts username with special characters', () {
      final dbName = DartCouchDb.usernameToDbName('bob@example.com');
      expect(dbName, startsWith('userdb-'));
      // Should be hex-encoded
      expect(dbName.length, greaterThan('userdb-'.length));
    });

    test('converts uppercase to lowercase', () {
      expect(
        DartCouchDb.usernameToDbName('dbreader'),
        equals("userdb-6462726561646572"),
      );
      expect(
        DartCouchDb.usernameToDbName('DBREADER'),
        equals("userdb-4442524541444552"),
      );
    });

    test('handles Unicode characters', () {
      final dbName = DartCouchDb.usernameToDbName('user_été');
      expect(dbName, startsWith('userdb-'));
    });

    test('roundtrip conversion preserves username', () {
      const username = 'alice';
      final dbName = DartCouchDb.usernameToDbName(username);
      final decoded = DartCouchDb.dbNameToUsername(dbName);
      expect(decoded, equals(username));
    });

    test('roundtrip with special characters', () {
      const username = 'bob@example.com';
      final dbName = DartCouchDb.usernameToDbName(username);
      final decoded = DartCouchDb.dbNameToUsername(dbName);
      expect(decoded, equals(username));
    });

    test('roundtrip with unicode', () {
      const username = 'café';
      final dbName = DartCouchDb.usernameToDbName(username);
      final decoded = DartCouchDb.dbNameToUsername(dbName);
      expect(decoded, equals(username));
    });

    test('decodes valid userdb- prefixed hex', () {
      expect(
        DartCouchDb.dbNameToUsername('userdb-616c696365'),
        equals('alice'),
      );
    });

    test('handles db name without userdb- prefix', () {
      // Should still try to decode as hex
      expect(DartCouchDb.dbNameToUsername('616c696365'), equals('alice'));
    });

    test('returns original string if not valid hex', () {
      const invalid = 'not-hex-data';
      expect(DartCouchDb.dbNameToUsername(invalid), equals(invalid));
    });

    test('handles empty string', () {
      final dbName = DartCouchDb.usernameToDbName('');
      expect(dbName, equals('userdb-'));
      expect(DartCouchDb.dbNameToUsername(dbName), equals(''));
    });
  });
}
