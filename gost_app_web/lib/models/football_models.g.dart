// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'football_models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CompetitionAdapter extends TypeAdapter<Competition> {
  @override
  final int typeId = 0;

  @override
  Competition read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Competition(
      id: fields[0] as int,
      name: fields[1] as String,
      emblemUrl: fields[2] as String?,
      code: fields[3] as String?,
      areaName: fields[4] as String?,
      areaFlag: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Competition obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.emblemUrl)
      ..writeByte(3)
      ..write(obj.code)
      ..writeByte(4)
      ..write(obj.areaName)
      ..writeByte(5)
      ..write(obj.areaFlag);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompetitionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TeamAdapter extends TypeAdapter<Team> {
  @override
  final int typeId = 1;

  @override
  Team read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Team(
      id: fields[0] as int,
      name: fields[1] as String,
      shortName: fields[2] as String,
      crestUrl: fields[3] as String?,
      tla: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Team obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.shortName)
      ..writeByte(3)
      ..write(obj.crestUrl)
      ..writeByte(4)
      ..write(obj.tla);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ScoreAdapter extends TypeAdapter<Score> {
  @override
  final int typeId = 2;

  @override
  Score read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Score(
      homeFullTime: fields[0] as int?,
      awayFullTime: fields[1] as int?,
      homeHalfTime: fields[2] as int?,
      awayHalfTime: fields[3] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, Score obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.homeFullTime)
      ..writeByte(1)
      ..write(obj.awayFullTime)
      ..writeByte(2)
      ..write(obj.homeHalfTime)
      ..writeByte(3)
      ..write(obj.awayHalfTime);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScoreAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class FootballMatchAdapter extends TypeAdapter<FootballMatch> {
  @override
  final int typeId = 3;

  @override
  FootballMatch read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FootballMatch(
      id: fields[0] as int,
      competition: fields[1] as Competition,
      homeTeam: fields[2] as Team,
      awayTeam: fields[3] as Team,
      score: fields[4] as Score,
      statusStr: fields[5] as String,
      utcDate: fields[6] as String,
      matchday: fields[7] as int?,
      minute: fields[8] as int?,
      stage: fields[9] as String?,
      group: fields[10] as String?,
      lastUpdated: fields[11] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, FootballMatch obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.competition)
      ..writeByte(2)
      ..write(obj.homeTeam)
      ..writeByte(3)
      ..write(obj.awayTeam)
      ..writeByte(4)
      ..write(obj.score)
      ..writeByte(5)
      ..write(obj.statusStr)
      ..writeByte(6)
      ..write(obj.utcDate)
      ..writeByte(7)
      ..write(obj.matchday)
      ..writeByte(8)
      ..write(obj.minute)
      ..writeByte(9)
      ..write(obj.stage)
      ..writeByte(10)
      ..write(obj.group)
      ..writeByte(11)
      ..write(obj.lastUpdated);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FootballMatchAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MatchEventAdapter extends TypeAdapter<MatchEvent> {
  @override
  final int typeId = 4;

  @override
  MatchEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MatchEvent(
      minute: fields[0] as int,
      type: fields[1] as String,
      detail: fields[2] as String?,
      playerName: fields[3] as String?,
      teamName: fields[4] as String?,
      isHomeTeam: fields[5] as bool,
      assistPlayerName: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MatchEvent obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.minute)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.detail)
      ..writeByte(3)
      ..write(obj.playerName)
      ..writeByte(4)
      ..write(obj.teamName)
      ..writeByte(5)
      ..write(obj.isHomeTeam)
      ..writeByte(6)
      ..write(obj.assistPlayerName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchEventAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MatchStatsAdapter extends TypeAdapter<MatchStats> {
  @override
  final int typeId = 5;

  @override
  MatchStats read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MatchStats(
      homePossession: fields[0] as int?,
      awayPossession: fields[1] as int?,
      homeShots: fields[2] as int?,
      awayShots: fields[3] as int?,
      homeShotsOnTarget: fields[4] as int?,
      awayShotsOnTarget: fields[5] as int?,
      homeCorners: fields[6] as int?,
      awayCorners: fields[7] as int?,
      homeFouls: fields[8] as int?,
      awayFouls: fields[9] as int?,
      homeXg: fields[10] as double?,
      awayXg: fields[11] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, MatchStats obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.homePossession)
      ..writeByte(1)
      ..write(obj.awayPossession)
      ..writeByte(2)
      ..write(obj.homeShots)
      ..writeByte(3)
      ..write(obj.awayShots)
      ..writeByte(4)
      ..write(obj.homeShotsOnTarget)
      ..writeByte(5)
      ..write(obj.awayShotsOnTarget)
      ..writeByte(6)
      ..write(obj.homeCorners)
      ..writeByte(7)
      ..write(obj.awayCorners)
      ..writeByte(8)
      ..write(obj.homeFouls)
      ..writeByte(9)
      ..write(obj.awayFouls)
      ..writeByte(10)
      ..write(obj.homeXg)
      ..writeByte(11)
      ..write(obj.awayXg);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchStatsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PlayerAdapter extends TypeAdapter<Player> {
  @override
  final int typeId = 6;

  @override
  Player read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Player(
      id: fields[0] as int,
      name: fields[1] as String,
      shirtNumber: fields[2] as int?,
      position: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Player obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.shirtNumber)
      ..writeByte(3)
      ..write(obj.position);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class LineupAdapter extends TypeAdapter<Lineup> {
  @override
  final int typeId = 7;

  @override
  Lineup read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Lineup(
      formation: fields[0] as String?,
      startingXI: (fields[1] as List).cast<Player>(),
      substitutes: (fields[2] as List).cast<Player>(),
      coach: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Lineup obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.formation)
      ..writeByte(1)
      ..write(obj.startingXI)
      ..writeByte(2)
      ..write(obj.substitutes)
      ..writeByte(3)
      ..write(obj.coach);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineupAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
