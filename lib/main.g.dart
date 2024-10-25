// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'main.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LaborAdapter extends TypeAdapter<Labor> {
  @override
  final int typeId = 1;

  @override
  Labor read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Labor(
      id: fields[0] as String?,
      name: fields[1] as String,
      dailyWage: fields[2] as double,
      advanceSalary: (fields[3] as Map?)?.cast<String, double>(),
      attendance: (fields[4] as Map?)?.cast<String, AttendanceType>(),
      phoneNumber: fields[5] as String?,
      department: fields[6] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Labor obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.dailyWage)
      ..writeByte(3)
      ..write(obj.advanceSalary)
      ..writeByte(4)
      ..write(obj.attendance)
      ..writeByte(5)
      ..write(obj.phoneNumber)
      ..writeByte(6)
      ..write(obj.department);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaborAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AttendanceTypeAdapter extends TypeAdapter<AttendanceType> {
  @override
  final int typeId = 0;

  @override
  AttendanceType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AttendanceType.absent;
      case 1:
        return AttendanceType.halfDay;
      case 2:
        return AttendanceType.fullDay;
      case 3:
        return AttendanceType.oneAndHalf;
      case 4:
        return AttendanceType.double;
      default:
        return AttendanceType.absent;
    }
  }

  @override
  void write(BinaryWriter writer, AttendanceType obj) {
    switch (obj) {
      case AttendanceType.absent:
        writer.writeByte(0);
        break;
      case AttendanceType.halfDay:
        writer.writeByte(1);
        break;
      case AttendanceType.fullDay:
        writer.writeByte(2);
        break;
      case AttendanceType.oneAndHalf:
        writer.writeByte(3);
        break;
      case AttendanceType.double:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttendanceTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
