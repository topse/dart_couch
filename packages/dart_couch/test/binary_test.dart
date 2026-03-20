import 'package:dart_couch/src/local_storage_engine/term_to_binary.dart';
import 'package:test/test.dart';

void main() {
  test('term_to_binary produces same output as Erlang', () {
    final bool = true;
    final int = 42;
    final map = {"foo": "bar", "num": 123};
    final array = [1, 2, 3];

    final bin = termToBinary([bool, int, map, array]);
    // print('Bin: ${bin.toList()}');

    // This is the exact output from Erlang term_to_binary([true, 42, #{"foo" => "bar", "num" => 123}, [1,2,3]])
    final expected = [
      131, // VERSION_MAGIC
      108, 0, 0, 0, 4, // LIST_EXT, length = 4 elements
      100, 0, 4, 116, 114, 117, 101, // ATOM_EXT: "true"
      97, 42, // SMALL_INTEGER_EXT: 42
      // SMALL_TUPLE_EXT, arity 1
      104, 1,
      // LIST_EXT, length 2
      108, 0, 0, 0, 2,
      // TUPLE_EXT, arity 2
      104, 2,
      109, 0, 0, 0, 3, 102, 111, 111, // BINARY "foo"
      109, 0, 0, 0, 3, 98, 97, 114, // BINARY "bar"
      // TUPLE_EXT, arity 2
      104, 2,
      109, 0, 0, 0, 3, 110, 117, 109, // BINARY "num"
      97, 123, // SMALL_INTEGER_EXT: 123
      106, // NIL_EXT for inner list tail
      107, 0, 3, 1, 2, 3, // STRING_EXT length 3: [1,2,3]
      106, // NIL_EXT (end of the outer list)
    ];

    /*
-module(hello).
-export([main/0]).

main() ->
    Bool = true,
    Int = 42,
    Map = #{"foo" => "bar", "num" => 123},
    Array = [1, 2, 3],
    BoolBin = term_to_binary([Bool, Int, Map, Array]),
    io:format("Bool: ~p~nBin: ~p~n~n", [Bool, BoolBin]).
*/
    // c(hello).
    // hello:main().

    expect(bin, equals(expected));
  });
}
