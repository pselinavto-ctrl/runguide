// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RunSessionAdapter extends TypeAdapter<RunSession> {
  @override
  final int typeId = 1;

  @override
  RunSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RunSession(
      id: fields[0] as String,
      date: fields[1] as DateTime,
      distance: fields[2] as double,
      duration: fields[3] as int,
      factsCount: fields[4] as int,
      route: (fields[5] as List).cast<RoutePoint>(),
      calories: fields[6] as int,
    );
  }

  @override
  void write(BinaryWriter writer, RunSession obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.distance)
      ..writeByte(3)
      ..write(obj.duration)
      ..writeByte(4)
      ..write(obj.factsCount)
      ..writeByte(5)
      ..write(obj.route)
      ..writeByte(6)
      ..write(obj.calories);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
