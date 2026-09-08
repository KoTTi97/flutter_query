/// The client's copy of the gateway's domain model.
///
/// Hand-written, with value equality and no code generation: the demo is also
/// the answer to "what does this library ask of my data types?", and the answer
/// is `==` and `hashCode`. That is what lets the cache tell a changed sensor
/// from an identical one and skip a rebuild
/// (https://github.com/KoTTi97/flutter_query/issues/12).
library;

import 'package:flutter/foundation.dart';

enum SensorType {
  contact('Kontakt'),
  motion('Bewegung'),
  temperature('Temperatur');

  const SensorType(this.label);

  final String label;

  static SensorType parse(Object? value) => SensorType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => SensorType.contact,
      );
}

@immutable
class Sensor {
  const Sensor({
    required this.id,
    required this.name,
    required this.type,
    required this.room,
    required this.battery,
    required this.temperature,
    required this.connected,
    required this.matterForwarding,
    required this.matterForwardingTarget,
    required this.matterForwardingPending,
  });

  factory Sensor.fromJson(Map<String, Object?> json) => Sensor(
        id: json['id']! as String,
        name: json['name']! as String,
        type: SensorType.parse(json['type']),
        room: json['room']! as String,
        battery: (json['battery']! as num).toInt(),
        temperature: (json['temperature']! as num).toDouble(),
        connected: json['connected']! as bool,
        matterForwarding: json['matterForwarding']! as bool,
        matterForwardingTarget: json['matterForwardingTarget'] as bool?,
        matterForwardingPending: json['matterForwardingPending']! as bool,
      );

  final String id;
  final String name;
  final SensorType type;
  final String room;
  final int battery;
  final double temperature;

  /// Reachable on the radio right now.
  final bool connected;

  /// Confirmed device state.
  final bool matterForwarding;

  /// The value a write is trying to reach, or `null` when nothing is
  /// outstanding.
  ///
  /// This exists so an in-flight write has somewhere to live that a poll
  /// response cannot overwrite. Without it the confirmed field is the only
  /// place to put the optimistic value, and every poll during the confirmation
  /// window stomps it back — the switch visibly flickers.
  final bool? matterForwardingTarget;

  /// The gateway accepted a write the device has not confirmed yet.
  final bool matterForwardingPending;

  /// What the Matter switch should render: a requested value outranks the
  /// confirmed one for as long as the write is outstanding.
  bool get displayedMatterForwarding =>
      matterForwardingTarget ?? matterForwarding;

  Sensor copyWith({
    String? name,
    bool? matterForwarding,
    bool? matterForwardingPending,
    bool? matterForwardingTarget,
    bool clearMatterForwardingTarget = false,
  }) =>
      Sensor(
        id: id,
        name: name ?? this.name,
        type: type,
        room: room,
        battery: battery,
        temperature: temperature,
        connected: connected,
        matterForwarding: matterForwarding ?? this.matterForwarding,
        matterForwardingTarget: clearMatterForwardingTarget
            ? null
            : (matterForwardingTarget ?? this.matterForwardingTarget),
        matterForwardingPending:
            matterForwardingPending ?? this.matterForwardingPending,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Sensor &&
          other.id == id &&
          other.name == name &&
          other.type == type &&
          other.room == room &&
          other.battery == battery &&
          other.temperature == temperature &&
          other.connected == connected &&
          other.matterForwarding == matterForwarding &&
          other.matterForwardingTarget == matterForwardingTarget &&
          other.matterForwardingPending == matterForwardingPending;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        type,
        room,
        battery,
        temperature,
        connected,
        matterForwarding,
        matterForwardingTarget,
        matterForwardingPending,
      );
}

@immutable
class SensorListResponse {
  const SensorListResponse({required this.sensors, required this.fetchedAt});

  factory SensorListResponse.fromJson(Map<String, Object?> json) =>
      SensorListResponse(
        sensors: (json['sensors']! as List<Object?>)
            .map((sensor) => Sensor.fromJson(sensor! as Map<String, Object?>))
            .toList(),
        fetchedAt: DateTime.parse(json['fetchedAt']! as String),
      );

  final List<Sensor> sensors;
  final DateTime fetchedAt;

  SensorListResponse withSensors(List<Sensor> sensors) =>
      SensorListResponse(sensors: sensors, fetchedAt: fetchedAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorListResponse &&
          other.fetchedAt == fetchedAt &&
          listEquals(other.sensors, sensors);

  @override
  int get hashCode => Object.hash(fetchedAt, Object.hashAll(sensors));
}

/// What the overview is filtered by. Part of the list's query key, so it needs
/// value equality like everything else in a key.
@immutable
class SensorFilters {
  const SensorFilters({this.search = '', this.room = 'all'});

  final String search;
  final String room;

  /// The unfiltered list. Anything asking for "all sensors" must use this
  /// exact value so it lands on the same key and shares the one cache entry.
  static const SensorFilters all = SensorFilters();

  Map<String, Object?> toJson() => <String, Object?>{
        'search': search,
        'room': room,
      };

  SensorFilters copyWith({String? search, String? room}) =>
      SensorFilters(search: search ?? this.search, room: room ?? this.room);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorFilters && other.search == search && other.room == room;

  @override
  int get hashCode => Object.hash(search, room);
}
