import 'package:dart_couch/dart_couch.dart' as dc;
import 'package:flutter/widgets.dart';

/// Bridges dart_couch's pure-Dart [dc.DcValueListenable] with Flutter's widget tree.
///
/// Works like Flutter's [ValueListenableBuilder] but accepts a
/// [dc.DcValueListenable] from the core dart_couch package.
class DcValueListenableBuilder<T> extends StatefulWidget {
  final dc.DcValueListenable<T> valueListenable;
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  const DcValueListenableBuilder({
    super.key,
    required this.valueListenable,
    required this.builder,
    this.child,
  });

  @override
  State<DcValueListenableBuilder<T>> createState() =>
      _DcValueListenableBuilderState<T>();
}

class _DcValueListenableBuilderState<T>
    extends State<DcValueListenableBuilder<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.valueListenable.value;
    widget.valueListenable.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(DcValueListenableBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valueListenable != widget.valueListenable) {
      oldWidget.valueListenable.removeListener(_onChanged);
      _value = widget.valueListenable.value;
      widget.valueListenable.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.valueListenable.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    setState(() {
      _value = widget.valueListenable.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _value, widget.child);
  }
}
