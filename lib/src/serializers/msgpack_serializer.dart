part of wamp_client;

class MsgPackSerializer extends Serializer {
  late WebSocket _webSocket; // Mark it as late

  MsgPackSerializer();

  @override
  Stream<List<dynamic>> read() async* {
    await for (final mm in _webSocket.onMessage) {
      var m = mm.data as ByteBuffer;
      yield unpack(m.asUint8List()) as List<dynamic>;
    }
  }

  @override
  void write(dynamic obj) {
    _webSocket.send(pack(obj));
  }

  @override
  set webSocket(WebSocket socket) {
    _webSocket = socket;
    _webSocket.binaryType = "arraybuffer";
  }
}
