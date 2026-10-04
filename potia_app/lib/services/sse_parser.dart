import 'dart:async';

class SseEvent {
  const SseEvent({required this.data, this.event});

  final String? event;
  final String data;
}

class SseParser extends StreamTransformerBase<String, SseEvent> {
  const SseParser();

  @override
  Stream<SseEvent> bind(Stream<String> lines) async* {
    String? eventName;
    final data = StringBuffer();
    var hasData = false;

    await for (final line in lines) {
      if (line.isEmpty) {
        if (hasData) yield SseEvent(event: eventName, data: data.toString());
        eventName = null;
        data.clear();
        hasData = false;
        continue;
      }
      if (line.startsWith(':')) continue;

      final separator = line.indexOf(':');
      final field = separator == -1 ? line : line.substring(0, separator);
      var value = separator == -1 ? '' : line.substring(separator + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      switch (field) {
        case 'data':
          if (hasData) data.write('\n');
          data.write(value);
          hasData = true;
        case 'event':
          eventName = value;
        default:
          break;
      }
    }
    if (hasData) yield SseEvent(event: eventName, data: data.toString());
  }
}
