part of msgpack;

Uint8List pack(value) {
  _statefulPacker ??= StatefulPacker();
  _statefulPacker.pack(value);
  return _statefulPacker.done();
}

late StatefulPacker _statefulPacker = StatefulPacker();

class PackedReference {
  final List<int> data;

  PackedReference(this.data);
}

class Float {
  final double value;

  Float(this.value);

  @override
  String toString() => value.toString();
}

class BinaryHelper {
  static ByteData? create(input) {
    if (input is ByteData) {
      return input;
    } else if (input is TypedData) {
      return input.buffer.asByteData(
        input.offsetInBytes,
        input.lengthInBytes,
      );
    } else if (input is ByteBuffer) {
      return input.asByteData();
    } else if (input is List<int>) {
      var bytes = Uint8List.fromList(input);
      return bytes.buffer.asByteData(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
    } else if (input is String) {
      var encoded = _toUTF8(input);
      if (encoded is Uint8List) {
        return encoded.buffer.asByteData(
          encoded.offsetInBytes,
          encoded.lengthInBytes,
        );
      } else {
        var bytes = Uint8List.fromList(encoded);
        return bytes.buffer.asByteData(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      }
    } else if (input == null) {
      return null;
    }

    throw Exception("Unsupported input to convert to binary");
  }
}

abstract class PackBuffer {
  void writeUint8(int b);
  void writeUint16(int value);
  void writeUint32(int value);
  void writeUint8List(Uint8List list);

  Uint8List done();
}

class MsgPackBuffer implements PackBuffer {
  static const int defaultBufferSize = int.fromEnvironment(
    "msgpack.packer.defaultBufferSize",
    defaultValue: 2048,
  );

  List<Uint8List> _buffers = <Uint8List>[];

  late Uint8List _buffer;
  int _len = 0;
  int _offset = 0;
  int _totalLength = 0;

  int _bufferId = 0;
  int _bufferCount = 0;

  final int bufferSize;

  MsgPackBuffer({this.bufferSize = defaultBufferSize}) {
    _buffer = Uint8List(bufferSize);
  }

  void _checkBuffer() {
    if (_buffer.lengthInBytes == _len) {
      if (_bufferId == _bufferCount) {
        _buffers.add(_buffer);
        _bufferCount++;
      } else {
        _buffers[_bufferId] = _buffer;
      }
      _bufferId++;
      _buffer = Uint8List(bufferSize);
      _len = 0;
      _offset = 0;
    }
  }

  @override
  void writeUint8(int byte) {
    _checkBuffer();

    _buffer[_offset] = byte;
    _offset++;
    _len++;
    _totalLength++;
  }

  @override
  void writeUint16(int value) {
    _checkBuffer();

    if ((_buffer.lengthInBytes - _len) < 2) {
      writeUint8((value >> 8) & 0xff);
      writeUint8(value & 0xff);
    } else {
      _buffer[_offset++] = (value >> 8) & 0xff;
      _buffer[_offset++] = value & 0xff;
      _len += 2;
      _totalLength += 2;
    }
  }

  @override
  void writeUint32(int value) {
    _checkBuffer();

    if ((_buffer.lengthInBytes - _len) < 4) {
      writeUint8((value >> 24) & 0xff);
      writeUint8((value >> 16) & 0xff);
      writeUint8((value >> 8) & 0xff);
      writeUint8(value & 0xff);
    } else {
      _buffer[_offset++] = (value >> 24) & 0xff;
      _buffer[_offset++] = (value >> 16) & 0xff;
      _buffer[_offset++] = (value >> 8) & 0xff;
      _buffer[_offset++] = value & 0xff;
      _len += 4;
      _totalLength += 4;
    }
  }

  Uint8List read() {
    if (_totalLength <= bufferSize) {
      return _buffer.buffer.asUint8List(0, _totalLength);
    }

    var out = Uint8List(_totalLength);
    var off = 0;

    for (var i = 0; i < _bufferCount; i++) {
      Uint8List buff = _buffers[i];

      for (var x = buff.offsetInBytes; x < buff.lengthInBytes; x++) {
        out[off++] = buff[x];
      }
    }

    for (var i = 0; i < _len; i++) {
      out[off++] = _buffer[i];
    }

    return out;
  }

  Uint8List reuse() {
    return done(reuse: true);
  }

  @override
  Uint8List done({bool reuse = false}) {
    Uint8List out = read();

    if (!reuse) {
      _buffers = <Uint8List>[];
      _bufferCount = 0;
    }

    _bufferId = 0;
    _len = 0;
    _totalLength = 0;
    _offset = 0;

    if (!reuse) {
      _buffer = Uint8List(bufferSize);
    }
    return out;
  }

  @override
  void writeUint8List(Uint8List data) {
    _checkBuffer();

    var dataSize = data.lengthInBytes;
    var bufferSpace = _buffer.lengthInBytes - _len;

    if (bufferSpace < dataSize) {
      var end = _offset + bufferSpace;
      _buffer.setRange(_offset, end, data);

      _len += bufferSpace;
      _totalLength += bufferSpace;

      var index = bufferSpace;
      var remain = dataSize - bufferSpace;

      while (index < dataSize) {
        _checkBuffer();

        if (_len == 0) {
          var ableToCopy = remain.clamp(0, bufferSize);
          _buffer.setRange(0, ableToCopy, data, index);
          _offset = ableToCopy;
          _len = ableToCopy;
          _totalLength += ableToCopy;
          index += ableToCopy;
          remain -= ableToCopy;
        } else {
          _buffer[_offset] = data[index++];
          _offset++;
          _len++;
          _totalLength++;
        }
      }
    } else {
      _buffer.setRange(_offset, _offset + dataSize, data);

      _offset += dataSize;
      _len += dataSize;
      _totalLength += dataSize;
    }
  }
}

class StatefulPacker {
  late PackBuffer buffer;

  StatefulPacker([PackBuffer? buffer]) {
    this.buffer = buffer ?? MsgPackBuffer();
  }

  void pack(value) {
    if (value is Iterable && value is! List) {
      value = value.toList();
    }

    if (value == null) {
      buffer.writeUint8(0xc0);
    } else if (value == false) {
      buffer.writeUint8(0xc2);
    } else if (value == true) {
      buffer.writeUint8(0xc3);
    } else if (value is int) {
      packInt(value);
    } else if (value is String) {
      packString(value);
    } else if (value is List) {
      packList(value);
    } else if (value is Map) {
      packMap(value);
    } else if (value is double) {
      packDouble(value);
    } else if (value is Float) {
      packFloat(value);
    } else if (value is ByteData) {
      packBinary(value);
    } else if (value is PackedReference) {
      writeAllBytes(value.data);
    } else {
      throw Exception("Failed to pack value: ${value}");
    }
  }

  void packAll(values) {
    for (var value in values) {
      pack(value);
    }
  }

  void packBinary(ByteData data) {
    var list = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    var count = list.lengthInBytes;

    if (count <= 255) {
      buffer.writeUint8(0xc4);
      buffer.writeUint8(count);
      writeAllBytes(list);
    } else if (count <= 65535) {
      buffer.writeUint8(0xc5);
      buffer.writeUint16(count);
      writeAllBytes(list);
    } else {
      buffer.writeUint8(0xc6);
      buffer.writeUint32(count);
      writeAllBytes(list);
    }
  }

  void packInt(int value) {
    if (value >= 0 && value < 128) {
      buffer.writeUint8(value);
      return;
    }

    if (value < 0) {
      if (value >= -32) {
        buffer.writeUint8(0xe0 + value + 32);
      } else if (value > -0x80) {
        buffer.writeUint8(0xd0);
        buffer.writeUint8(value + 0x100);
      } else if (value > -0x8000) {
        buffer.writeUint8(0xd1);
        buffer.writeUint16(value + 0x10000);
      } else if (value > -0x80000000) {
        buffer.writeUint8(0xd2);
        buffer.writeUint32(value + 0x100000000);
      } else {
        buffer.writeUint8(0xd3);
        _encodeUint64(value);
      }
    } else {
      if (value < 0x100) {
        buffer.writeUint8(0xcc);
        buffer.writeUint8(value);
      } else if (value < 0x10000) {
        buffer.writeUint8(0xcd);
        buffer.writeUint16(value);
      } else if (value < 0x100000000) {
        buffer.writeUint8(0xce);
        buffer.writeUint32(value);
      } else {
        buffer.writeUint8(0xcf);
        _encodeUint64(value);
      }
    }
  }

  void _encodeUint64(int value) {
    var high = (value / 0x100000000).floor();
    var low = value & 0xffffffff;
    buffer.writeUint8((high >> 24) & 0xff);
    buffer.writeUint8((high >> 16) & 0xff);
    buffer.writeUint8((high >> 8) & 0xff);
    buffer.writeUint8(high & 0xff);
    buffer.writeUint8((low >> 24) & 0xff);
    buffer.writeUint8((low >> 16) & 0xff);
    buffer.writeUint8((low >> 8) & 0xff);
    buffer.writeUint8(low & 0xff);
  }

  void packString(String value) {
    List<int> utf8;

    if (StringCache.has(value)) {
      utf8 = StringCache.get(value)!;
    } else {
      utf8 = _toUTF8(value);
    }

    if (utf8.length < 0x20) {
      buffer.writeUint8(0xa0 + utf8.length);
    } else if (utf8.length < 0x100) {
      buffer.writeUint8(0xd9);
      buffer.writeUint8(utf8.length);
    } else if (utf8.length < 0x10000) {
      buffer.writeUint8(0xda);
      buffer.writeUint16(utf8.length);
    } else {
      buffer.writeUint8(0xdb);
      buffer.writeUint32(utf8.length);
    }
    writeAllBytes(utf8);
  }

  void packDouble(double value) {
    buffer.writeUint8(0xcb);
    var f = ByteData(8);
    f.setFloat64(0, value);
    writeAllBytes(f);
  }

  void packFloat(Float float) {
    buffer.writeUint8(0xca);
    var f = ByteData(4);
    f.setFloat32(0, float.value);
    writeAllBytes(f);
  }

  void packList(List value) {
    var len = value.length;
    if (len < 16) {
      buffer.writeUint8(0x90 + len);
    } else if (len < 0x100) {
      buffer.writeUint8(0xdc);
      buffer.writeUint16(len);
    } else {
      buffer.writeUint8(0xdd);
      buffer.writeUint32(len);
    }

    for (var i = 0; i < len; i++) {
      pack(value[i]);
    }
  }

  void packMap(Map value) {
    if (value.length < 16) {
      buffer.writeUint8(0x80 + value.length);
    } else if (value.length < 0x100) {
      buffer.writeUint8(0xde);
      buffer.writeUint16(value.length);
    } else {
      buffer.writeUint8(0xdf);
      buffer.writeUint32(value.length);
    }

    for (var element in value.keys) {
      pack(element);
      pack(value[element]);
    }
  }

  void writeAllBytes(list) {
    if (list is Uint8List) {
      buffer.writeUint8List(list);
    } else if (list is ByteData) {
      buffer.writeUint8List(list.buffer.asUint8List(
        list.offsetInBytes,
        list.lengthInBytes,
      ));
    } else if (list is List) {
      for (var b in list) {
        buffer.writeUint8(b);
      }
    } else {
      throw Exception("I don't know how to write everything in ${list}");
    }
  }

  Uint8List done() {
    return buffer.done();
  }
}
