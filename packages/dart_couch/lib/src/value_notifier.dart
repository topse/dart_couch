/// Pure-Dart implementation of ValueNotifier/ValueListenable,
/// prefixed with Dc to avoid name conflicts with Flutter's equivalents.
library;

abstract class DcListenable {
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}

abstract class DcValueListenable<T> extends DcListenable {
  T get value;
}

class DcValueNotifier<T> implements DcValueListenable<T> {
  DcValueNotifier(this._value);

  final List<void Function()> _listeners = [];

  @override
  T get value => _value;
  T _value;

  set value(T newValue) {
    if (_value == newValue) return;
    _value = newValue;
    notifyListeners();
  }

  @override
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void notifyListeners() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  void dispose() {
    _listeners.clear();
  }
}
