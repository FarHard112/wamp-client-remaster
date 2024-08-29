part of wamp_client;

class JsonSerializer extends Serializer {
  late WebSocket _webSocket;
  JsonSerializer();

  @override
  Stream<List<dynamic>> read() async* {
    await for (final mm in _webSocket.onMessage) {
      var m = mm.data.toString();
      final s = m is String ? m : new Utf8Decoder().convert(m as List<int>);
      yield json.decode(s) as List<dynamic>;
    }
  }

  @override
  void write(dynamic obj) {
    _webSocket.send(json.encode(obj, toEncodable: _encode));
  }

  @override
  set webSocket(WebSocket socket) {
    _webSocket = socket;
  }

  dynamic _encode(dynamic item) {
    if (item is DateTime) {
      return item.toIso8601String();
    }
    return item;
  }
}
