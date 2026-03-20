import 'dart:typed_data';
import 'dart:convert';

/// Enum for Erlang external term format opcodes, sorted by byte value.
/// See: https://www.erlang.org/doc/apps/erts/erl_ext_dist.html
enum ErlangExternalTag {
  bitBinary(77), // 'M'
  compressedTerm(80), // 'P'
  newFun(112), // 'p'
  export(113), // 'q'
  newReference(114), // 'r'
  smallAtom(115), // 's'
  map(116), // 't'
  fun(117), // 'u'
  atomUtf8(118), // 'v'
  smallAtomUtf8(119), // 'w'
  v4Port(120), // 'x'
  newPid(88), // 'X'
  newPort(89), // 'Y'
  newerReference(90), // 'Z'
  smallInteger(97), // 'a'
  integer(98), // 'b'
  floatDeprecated(99), // 'c' (deprecated)
  atom(100), // 'd'
  reference(101), // 'e'
  port(102), // 'f'
  pid(103), // 'g'
  smallTuple(104), // 'h'
  largeTuple(105), // 'i'
  nil(106), // 'j' (empty list)
  string(107), // 'k'
  list(108), // 'l'
  binary(109), // 'm'
  smallBig(110), // 'n'
  largeBig(111), // 'o'
  newFloat(70); // 'F' (IEEE 754 double)

  final int code;
  const ErlangExternalTag(this.code);

  static ErlangExternalTag? fromCode(int code) {
    return ErlangExternalTag.values.firstWhere((e) => e.code == code);
  }
}

/// Implements Erlang's term_to_binary for the subset of types needed for CouchDB
/// See: https://erlang.org/doc/apps/erts/erl_ext_dist.html
Uint8List termToBinary(dynamic term) {
  final bytes = BytesBuilder();
  bytes.addByte(131); // VERSION_MAGIC
  _encodeTerm(bytes, term);
  return bytes.toBytes();
}

void _encodeTerm(BytesBuilder bytes, dynamic term) {
  if (term == null) {
    _encodeAtom(bytes, 'nil'); // Erlang uses 'nil' atom for null
  } else if (term is bool) {
    _encodeAtom(bytes, term ? 'true' : 'false');
  } else if (term is int || term is BigInt) {
    if (term is int && term >= 0 && term <= 255) {
      bytes.addByte(ErlangExternalTag.smallInteger.code); // SMALL_INTEGER_EXT
      bytes.addByte(term);
    } else if (term is int && term >= -2147483648 && term <= 2147483647) {
      bytes.addByte(ErlangExternalTag.integer.code); // INTEGER_EXT
      bytes.add(_int32(term));
    } else {
      encodeSmallBigExt(bytes, term is BigInt ? term : BigInt.from(term));
    }
  } else if (term is double) {
    bytes.addByte(ErlangExternalTag.newFloat.code); // NEW_FLOAT_EXT
    final bd = ByteData(8);
    bd.setFloat64(0, term, Endian.big);
    bytes.add(bd.buffer.asUint8List());
  } else if (term is String) {
    final strBytes = utf8.encode(term);

    bytes.addByte(ErlangExternalTag.binary.code); // BINARY_EXT
    bytes.add(_int32(strBytes.length));

    bytes.add(strBytes);
  } else if (term is Uint8List) {
    bytes.addByte(ErlangExternalTag.binary.code); // BINARY_EXT
    bytes.add(_int32(term.length));
    bytes.add(term);
  } else if (term is Set) {
    bytes.addByte(ErlangExternalTag.smallTuple.code); // SMALL_TUPLE_EXT
    bytes.add([term.length]); // number of elements in the tuple
    for (final item in term) {
      _encodeTerm(bytes, item);
    }
  } else if (term is List) {
    if (term.isEmpty) {
      bytes.addByte(ErlangExternalTag.nil.code); // NIL_EXT
    } else {
      bool allIsBytes = term.every((e) => e is int && e >= 0 && e <= 255);
      if (allIsBytes) {
        bytes.addByte(ErlangExternalTag.string.code); // STRING_EXT
        bytes.add(_int16(term.length));
        bytes.add(term.cast<int>());
      } else {
        bytes.addByte(ErlangExternalTag.list.code); // LIST_EXT
        bytes.add(_int32(term.length));
        for (var item in term) {
          _encodeTerm(bytes, item);
        }
        bytes.addByte(
          ErlangExternalTag.nil.code,
        ); // NIL_EXT to Terminate the list
      }
    }
  } else if (term is Map) {
    if (term.isEmpty) {
      bytes.addByte(ErlangExternalTag.smallTuple.code); // SMALL_TUPLE_EXT
      bytes.add([1]); // 1 element in the tuple
      bytes.addByte(ErlangExternalTag.nil.code); // NIL_EXT
      return;
    }

    // if its a map its the body of a document, so wrap it in a tuple
    // to match CouchDB's encoding
    bytes.addByte(ErlangExternalTag.smallTuple.code); // SMALL_TUPLE_EXT
    bytes.add([1]); // 1 element in the tuple

    // now encode the map itself
    bytes.addByte(ErlangExternalTag.list.code); // LIST_EXT
    bytes.add(_int32(term.length));

    // key-value pairs
    for (var key in term.keys) {
      if (key is! String) {
        throw ArgumentError('Map keys must be strings: $key');
      }
      // encode pair
      bytes.addByte(ErlangExternalTag.smallTuple.code); // SMALL_TUPLE_EXT
      bytes.add([2]); // 2 elements in the tuple (key, value)
      // encode key
      bytes.addByte(ErlangExternalTag.binary.code); // STRING_EXT
      bytes.add(_int32(key.length));
      bytes.add(utf8.encode(key));
      // encode value
      _encodeTerm(bytes, term[key]);
    }
    bytes.addByte(ErlangExternalTag.nil.code); // NIL_EXT to Terminate the list
  } else {
    throw ArgumentError('Unsupported type: ${term.runtimeType}');
  }
}

void _encodeAtom(BytesBuilder bytes, String atom) {
  final atomBytes = utf8.encode(atom);
  if (atomBytes.length > 255) {
    throw ArgumentError('Atom too long: $atom');
  }
  bytes.addByte(ErlangExternalTag.atom.code);
  assert(atomBytes.length <= 65535);
  bytes.add(_int16(atomBytes.length));
  bytes.add(atomBytes);
}

List<int> _int16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

List<int> _int32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

void encodeSmallBigExt(BytesBuilder bytes, BigInt value) {
  // Determine sign: 0 for positive, 1 for negative
  final int signByte = value.isNegative ? 1 : 0;

  // Get absolute value
  BigInt absValue = value.abs();

  // Convert to little-endian byte list
  final digitBytes = <int>[];

  if (absValue == BigInt.zero) {
    digitBytes.add(0);
  } else {
    while (absValue > BigInt.zero) {
      digitBytes.add((absValue & BigInt.from(0xFF)).toInt());
      absValue = absValue >> 8;
    }
  }

  final int n = digitBytes.length;

  // Build result using BytesBuilder
  bytes.addByte(ErlangExternalTag.smallBig.code); // Tag: SMALL_BIG_EXT
  bytes.addByte(n); // Arity: number of digits
  bytes.addByte(signByte); // Sign byte
  bytes.add(digitBytes); // Digit bytes in little-endian order
}
