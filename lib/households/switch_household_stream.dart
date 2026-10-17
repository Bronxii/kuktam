import 'dart:async';

/// Cancel old household delivery before binding the next confirmed context.
Stream<T> switchHouseholdStream<T>(
  Stream<String> contexts,
  Stream<T> Function(String) open,
) {
  late StreamController<T> result;
  StreamSubscription<String>? outer;
  StreamSubscription<T>? inner;
  var epoch = 0;
  var stopped = false;
  result = StreamController<T>(
    onListen: () {
      outer = contexts.distinct().listen(
        (id) {
          final generation = ++epoch;
          unawaited(inner?.cancel());
          if (stopped || generation != epoch) return;
          inner = open(id).listen(
            (value) {
              if (!stopped && generation == epoch) result.add(value);
            },
            onError: (Object error, StackTrace stack) {
              if (!stopped && generation == epoch) {
                result.addError(error, stack);
              }
            },
          );
        },
        onError: (Object error, StackTrace stack) {
          epoch++;
          unawaited(inner?.cancel());
          if (!stopped) result.addError(error, stack);
        },
      );
    },
    onCancel: () {
      stopped = true;
      epoch++;
      unawaited(outer?.cancel());
      unawaited(inner?.cancel());
    },
  );
  return result.stream;
}
