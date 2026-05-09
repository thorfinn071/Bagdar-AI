import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/constants.dart';
import '../models/nav_models.dart';
import '../models/strings.dart';
import 'compass_service.dart';
import 'step_service.dart';

enum NavState { idle, navigating, paused, arrivedWalk }

enum TransitNavPhase { walkToStop, waitForBus, riding, walkFromStop, done }

class NavigationService {
  final CompassService compass;
  final StepService? stepService;

  NavState _state = NavState.idle;
  NavState get state => _state;

  NavRoute? _route;
  NavRoute? get route => _route;

  TransitRoute? _transitRoute;
  TransitRoute? get transitRoute => _transitRoute;

  int _currentStepIndex = 0;
  int get currentStepIndex => _currentStepIndex;

  RouteStep? get currentStep =>
      _route != null && _currentStepIndex < _route!.steps.length
      ? _route!.steps[_currentStepIndex]
      : null;

  TransitNavPhase _transitPhase = TransitNavPhase.done;
  TransitNavPhase get transitPhase => _transitPhase;
  int _transitLegIndex = 0;
  int _transitStopCounter = 0;

  StreamSubscription<Position>? _gpsSub;
  Position? _lastPosition;
  int _lastPositionStepCount = 0;

  void Function(String instruction)? onInstruction;
  void Function(Position pos)? onPositionUpdated;
  void Function()? onArrived;
  void Function()? onOffRoute;
  void Function()? onSoftOffRoute;
  void Function(int stepsRemaining, int metersRemaining)? onProgress;

  void Function(String instruction)? onTransitInstruction;
  void Function()? onTransitArrived;
  void Function(String routeNumber, String stopName)? onBusWait;

  Future<NavRoute?> Function(double fromLat, double fromLng)?
  onRerouteRequested;

  void Function(double bearingDeg, int distanceMeters)? onOffRouteBearing;

  static const double _stepProximity = 20.0;
  static const double _arrivalProximity = 15.0;
  static const double _offRouteThreshold = 25.0;
  static const double _softOffRouteThreshold = 15.0;
  static const double _transitStopProximity = 40.0;

  static const double _driftDistanceThreshold = 35.0;
  static const int _driftMinStepsRequired = 5;

  static const Duration _offRouteCooldown = Duration(seconds: 30);
  static const Duration _softOffRouteCooldown = Duration(seconds: 15);
  static const Duration _rerouteCooldown = Duration(seconds: 60);
  DateTime _lastOffRouteAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSoftOffRouteAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRerouteAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _rerouteInFlight = false;

  DateTime _lastInstructionAt = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastProgressSteps = -1;
  int _lastProgressMeters = -1;
  static const Duration _progressInterval = Duration(seconds: 20);

  DateTime _lastFixAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _navMuted = false;
  DateTime _lastNavMuteChangeAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _navMuteFlapGuard = Duration(seconds: 10);

  void Function(String message)? onNavMuteChanged;

  NavigationService({required this.compass, this.stepService});

  void startWalkNavigation(NavRoute route) {
    stopNavigation();
    _route = route;
    _currentStepIndex = 0;
    _state = NavState.navigating;
    _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastProgressSteps = -1;
    _lastProgressMeters = -1;
    _lastPositionStepCount = stepService?.steps ?? 0;

    final totalDist = route.totalDistanceMeters;
    final mins = (route.totalDurationSeconds / 60).ceil();
    final dest = route.destinationName.isNotEmpty
        ? route.destinationName
        : S.get('nav_destination');

    onInstruction?.call(
      '${S.get('nav_route_built')} $dest. '
      '$totalDist ${S.get('meters')}. '
      '${S.get('nav_approx')} $mins ${S.get('nav_minutes')}.',
    );

    _announceCurrentStep();
    _startGpsTracking();
    debugPrint(
      'NavigationService: walk nav started, ${route.steps.length} steps',
    );
  }

  void startTransitNavigation(TransitRoute transitRoute) {
    stopNavigation();
    _transitRoute = transitRoute;
    _transitLegIndex = 0;
    _transitStopCounter = 0;
    _state = NavState.navigating;
    _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastProgressSteps = -1;
    _lastProgressMeters = -1;
    _lastPositionStepCount = stepService?.steps ?? 0;

    final mins = (transitRoute.totalDurationSeconds / 60).ceil();
    final dest = transitRoute.destinationName.isNotEmpty
        ? transitRoute.destinationName
        : S.get('nav_destination');

    onTransitInstruction?.call(
      '${S.get('nav_transit_route_built')} $dest. '
      '${S.get('nav_approx')} $mins ${S.get('nav_minutes')}.',
    );

    _advanceTransitLeg();
    _startGpsTracking();
    debugPrint(
      'NavigationService: transit nav started, ${transitRoute.legs.length} legs',
    );
  }

  void stopNavigation() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _state = NavState.idle;
    _route = null;
    _transitRoute = null;
    _currentStepIndex = 0;
    _transitLegIndex = 0;
    _transitStopCounter = 0;
    _transitPhase = TransitNavPhase.done;
    _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastProgressSteps = -1;
    _lastProgressMeters = -1;
    _lastPositionStepCount = 0;
    _lastOffRouteAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSoftOffRouteAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastRerouteAt = DateTime.fromMillisecondsSinceEpoch(0);
    _rerouteInFlight = false;
    _lastFixAt = DateTime.fromMillisecondsSinceEpoch(0);
    _navMuted = false;
    _lastNavMuteChangeAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void pauseNavigation() {
    if (_state == NavState.navigating) {
      _state = NavState.paused;
      _gpsSub?.pause();
    }
  }

  void resumeNavigation() {
    if (_state == NavState.paused) {
      _state = NavState.navigating;
      _gpsSub?.resume();
    }
  }

  String getStatusSummary() {
    if (_state != NavState.navigating) return S.get('nav_not_active');

    if (_route != null) {
      final step = currentStep;
      if (step == null) return S.get('nav_arriving');
      final remaining = _remainingDistance();
      return '${S.get('nav_remaining')} $remaining ${S.get('meters')}.';
    }

    if (_transitRoute != null) {
      return _transitStatusSummary();
    }

    return S.get('nav_not_active');
  }

  String getWhereAmI() {
    if (_lastPosition == null) return S.get('nav_no_gps');
    final lat = _lastPosition!.latitude.toStringAsFixed(4);
    final lng = _lastPosition!.longitude.toStringAsFixed(4);
    return '${S.get('nav_your_position')} $lat, $lng.';
  }

  void Function(String message)? onGpsError;

  void _startGpsTracking() {
    _gpsSub?.cancel();
    _gpsSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen(
          _onPositionUpdate,
          onError: (e) {
            debugPrint('NavigationService: GPS error $e');
            onGpsError?.call(S.get('nav_no_gps'));
          },
        );
  }

  void _onPositionUpdate(Position pos) {
    final now = DateTime.now();

    _lastFixAt = now;

    final gpsBad = pos.accuracy > kNavGpsAccuracyMaxM ||
        (_lastFixAt.millisecondsSinceEpoch != 0 &&
            now.difference(_lastFixAt) > const Duration(seconds: kNavGpsMaxAgeSec));

    if (gpsBad && !_navMuted) {
      if (now.difference(_lastNavMuteChangeAt) >= _navMuteFlapGuard) {
        _navMuted = true;
        _lastNavMuteChangeAt = now;
        onNavMuteChanged?.call(S.get('nav_gps_unreliable'));
      }
    } else if (!gpsBad && _navMuted) {
      if (now.difference(_lastNavMuteChangeAt) >= _navMuteFlapGuard) {
        _navMuted = false;
        _lastNavMuteChangeAt = now;
        onNavMuteChanged?.call(S.get('nav_gps_restored'));
      }
    }

    if (_lastPosition != null && _transitRoute == null) {
      final distanceMoved = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );

      if (distanceMoved > _driftDistanceThreshold && pos.speed < 7.0) {
        final currentSteps = stepService?.steps ?? 0;
        final stepsTaken = currentSteps - _lastPositionStepCount;

        if (stepsTaken < _driftMinStepsRequired) {
          debugPrint(
            'NavigationService: GPS Drift detected (moved ${distanceMoved.toStringAsFixed(1)}m, steps=$stepsTaken). Skipping update.',
          );
          return;
        }
      }
    }

    _lastPosition = pos;
    _lastPositionStepCount = stepService?.steps ?? 0;

    onPositionUpdated?.call(pos);
    if (_state != NavState.navigating) return;

    if (_navMuted) return;

    if (_transitRoute != null) {
      _handleTransitPosition(pos);
    } else if (_route != null) {
      if (_handleWalkPosition(pos)) {
        stopNavigation();
      }
    }
  }

  bool _handleWalkPosition(Position pos, {bool isTransitLeg = false}) {
    final route = _route!;
    if (_currentStepIndex >= route.steps.length) return false;

    final lastStep = route.steps.last;
    final distToEnd = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      lastStep.endLat,
      lastStep.endLng,
    );

    if (distToEnd <= _arrivalProximity) {
      _state = NavState.arrivedWalk;
      if (!isTransitLeg) {
        final dest = route.destinationName.isNotEmpty
            ? route.destinationName
            : S.get('nav_destination');
        onInstruction?.call('${S.get('nav_arrived')} $dest.');
        onArrived?.call();
      }
      return true;
    }

    final step = route.steps[_currentStepIndex];
    final distToStepEnd = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      step.endLat,
      step.endLng,
    );

    if (distToStepEnd <= _stepProximity) {
      _currentStepIndex++;
      if (_currentStepIndex < route.steps.length) {
        _announceCurrentStep();
      }
      return false;
    }

    final distToStepStart = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      step.startLat,
      step.startLng,
    );
    if (distToStepStart > _offRouteThreshold &&
        distToStepEnd > _offRouteThreshold) {
      _handleOffRoute(pos, step, distToStepStart);
    } else if (distToStepStart > _softOffRouteThreshold &&
        distToStepEnd > _softOffRouteThreshold) {
      _handleSoftOffRoute();
    }

    final now = DateTime.now();
    if (now.difference(_lastProgressAt) >= _progressInterval) {
      final remaining = _remainingDistance();
      final stepsLeft = route.steps.length - _currentStepIndex;
      final progressChanged =
          _lastProgressSteps != stepsLeft ||
          (_lastProgressMeters < 0 ||
              (remaining - _lastProgressMeters).abs() >= 10);

      if (progressChanged) {
        _lastProgressAt = now;
        _lastProgressSteps = stepsLeft;
        _lastProgressMeters = remaining;
        onProgress?.call(stepsLeft, remaining);
      }
    }

    if (now.difference(_lastInstructionAt) >= const Duration(seconds: 30)) {
      _announceApproach(pos, step, distToStepEnd.round());
    }
    return false;
  }

  void _handleSoftOffRoute() {
    final now = DateTime.now();
    if (now.difference(_lastSoftOffRouteAt) < _softOffRouteCooldown) return;
    _lastSoftOffRouteAt = now;
    onSoftOffRoute?.call();
  }

  void _handleOffRoute(Position pos, RouteStep step, double distToStepStart) {
    final now = DateTime.now();
    if (now.difference(_lastOffRouteAt) < _offRouteCooldown) return;
    _lastOffRouteAt = now;
    onOffRoute?.call();

    if (onOffRouteBearing != null) {
      final target = _nearestStepStart(pos);
      if (target != null) {
        final bearing = _bearing(
          pos.latitude,
          pos.longitude,
          target.$1,
          target.$2,
        );
        onOffRouteBearing!(bearing, target.$3.round());
      }
    }

    if (onRerouteRequested != null &&
        !_rerouteInFlight &&
        now.difference(_lastRerouteAt) >= _rerouteCooldown) {
      _lastRerouteAt = now;
      _rerouteInFlight = true;
      unawaited(_tryReroute(pos));
    }
  }

  Future<void> _tryReroute(Position pos) async {
    try {
      final newRoute = await onRerouteRequested!(pos.latitude, pos.longitude);
      if (newRoute == null || newRoute.steps.isEmpty) {
        onInstruction?.call(S.get('nav_reroute_failed'));
        return;
      }
      _route = newRoute;
      _currentStepIndex = 0;
      _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
      _lastProgressSteps = -1;
      _lastProgressMeters = -1;
      onInstruction?.call(S.get('nav_reroute_ok'));
      _announceCurrentStep();
    } catch (e) {
      
      debugPrint('NavigationService: reroute failed: $e');
      onInstruction?.call(S.get('nav_reroute_failed'));
    } finally {
      _rerouteInFlight = false;
    }
  }

  (double lat, double lng, double distance)? _nearestStepStart(Position pos) {
    final route = _route;
    if (route == null || route.steps.isEmpty) return null;
    double bestDist = double.infinity;
    double bestLat = 0, bestLng = 0;
    for (final s in route.steps) {
      final d = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        s.startLat,
        s.startLng,
      );
      if (d < bestDist) {
        bestDist = d;
        bestLat = s.startLat;
        bestLng = s.startLng;
      }
    }
    if (bestDist.isInfinite) return null;
    return (bestLat, bestLng, bestDist);
  }

  static double _bearing(double lat1, double lng1, double lat2, double lng2) {
    final dLng = _toRad(lng2 - lng1);
    final y = math.sin(dLng) * math.cos(_toRad(lat2));
    final x =
        math.cos(_toRad(lat1)) * math.sin(_toRad(lat2)) -
        math.sin(_toRad(lat1)) * math.cos(_toRad(lat2)) * math.cos(dLng);
    return (_toDeg(math.atan2(y, x)) + 360) % 360;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
  static double _toDeg(double rad) => rad * 180 / math.pi;

  void _announceCurrentStep() {
    if (_route == null || _currentStepIndex >= _route!.steps.length) return;
    final step = _route!.steps[_currentStepIndex];
    final dir = _maneuverToText(step.maneuver);
    final dist = step.distanceMeters;

    String msg;
    if (step.instruction.isNotEmpty) {
      msg = '${step.instruction}. $dist ${S.get('meters')}.';
    } else {
      msg = '$dir. $dist ${S.get('meters')}.';
    }

    _lastInstructionAt = DateTime.now();
    onInstruction?.call(msg);
  }

  void _announceApproach(Position pos, RouteStep step, int distToEnd) {
    if (!compass.isAvailable) {
      _lastInstructionAt = DateTime.now();
      return;
    }

    final bearing = compass.bearingTo(
      pos.latitude,
      pos.longitude,
      step.endLat,
      step.endLng,
    );
    final relDir = compass.relativeDirection(compass.heading, bearing);
    final dirText = _relDirToText(relDir);

    _lastInstructionAt = DateTime.now();
    onInstruction?.call('$dirText. $distToEnd ${S.get('meters')}.');
  }

  int _remainingDistance() {
    if (_route == null) return 0;
    int dist = 0;
    for (int i = _currentStepIndex; i < _route!.steps.length; i++) {
      dist += _route!.steps[i].distanceMeters;
    }
    return dist;
  }

  void _handleTransitPosition(Position pos) {
    final tr = _transitRoute!;
    if (_transitLegIndex >= tr.legs.length) return;

    final leg = tr.legs[_transitLegIndex];

    switch (_transitPhase) {
      case TransitNavPhase.walkToStop:
        _handleWalkToStop(pos, leg);
      case TransitNavPhase.waitForBus:
        if (pos.speed > 3.0) {
          _transitPhase = TransitNavPhase.riding;
          _transitStopCounter = 0;
          onTransitInstruction?.call(S.get('nav_auto_boarded'));
        }
        break;
      case TransitNavPhase.riding:
        _handleRiding(pos, leg);
      case TransitNavPhase.walkFromStop:
        _handleWalkFromStop(pos);
      case TransitNavPhase.done:
        break;
    }
  }

  void _handleWalkToStop(Position pos, TransitLeg leg) {
    if (_route != null) {
      if (_handleWalkPosition(pos, isTransitLeg: true)) {
        _state = NavState.navigating;
        _route = null;
        _transitPhase = TransitNavPhase.waitForBus;
        final routeNum = leg.routeNumber ?? leg.routeName ?? '';
        onTransitInstruction?.call('${S.get('nav_wait_bus')} $routeNum.');
      }
      return;
    }

    if (leg.departureStop != null) {
      final dist = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        leg.departureStop!.lat,
        leg.departureStop!.lng,
      );
      if (dist <= _transitStopProximity) {
        _transitPhase = TransitNavPhase.waitForBus;
        final routeNum = leg.routeNumber ?? leg.routeName ?? '';
        onTransitInstruction?.call(
          '${S.get('nav_at_stop')} ${leg.departureStop!.name}. '
          '${S.get('nav_wait_bus')} $routeNum.',
        );
      }
    }
  }

  void _handleRiding(Position pos, TransitLeg leg) {
    if (leg.arrivalStop != null) {
      final distToArrival = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        leg.arrivalStop!.lat,
        leg.arrivalStop!.lng,
      );

      if (distToArrival <= _transitStopProximity) {
        onTransitInstruction?.call(
          '${S.get('nav_exit_now')} ${leg.arrivalStop!.name}.',
        );
        _transitLegIndex++;
        _advanceTransitLeg();
        return;
      }

      for (int i = _transitStopCounter; i < leg.intermediateStops.length; i++) {
        final stop = leg.intermediateStops[i];
        final dist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          stop.lat,
          stop.lng,
        );
        if (dist <= _transitStopProximity) {
          _transitStopCounter = i + 1;
          final remaining =
              leg.intermediateStops.length - _transitStopCounter + 1;
          onTransitInstruction?.call(
            '${stop.name}. ${S.get('nav_stops_remaining')} $remaining.',
          );
          break;
        }
      }
    }
  }

  void _handleWalkFromStop(Position pos) {
    if (_route != null) {
      if (_handleWalkPosition(pos, isTransitLeg: true)) {
        _transitPhase = TransitNavPhase.done;
        final dest = _transitRoute?.destinationName ?? S.get('nav_destination');
        onTransitInstruction?.call('${S.get('nav_arrived')} $dest.');
        onTransitArrived?.call();
        stopNavigation();
      }
    }
  }

  void _advanceTransitLeg() {
    final tr = _transitRoute!;
    if (_transitLegIndex >= tr.legs.length) {
      _transitPhase = TransitNavPhase.done;
      final dest = tr.destinationName.isNotEmpty
          ? tr.destinationName
          : S.get('nav_destination');
      onTransitInstruction?.call('${S.get('nav_arrived')} $dest.');
      onTransitArrived?.call();
      stopNavigation();
      return;
    }

    final leg = tr.legs[_transitLegIndex];
    _transitStopCounter = 0;

    if (leg.isWalk) {
      if (leg.walkSteps.isNotEmpty) {
        final walkRoute = NavRoute(
          steps: leg.walkSteps,
          totalDistanceMeters: leg.distanceMeters,
          totalDurationSeconds: leg.durationSeconds,
          destinationName:
              leg.departureStop?.name ?? leg.arrivalStop?.name ?? '',
        );
        _route = walkRoute;
        _currentStepIndex = 0;

        if (_transitLegIndex == tr.legs.length - 1) {
          _transitPhase = TransitNavPhase.walkFromStop;
        } else {
          _transitPhase = TransitNavPhase.walkToStop;
        }

        onTransitInstruction?.call(
          '${S.get('nav_walk')} ${leg.distanceMeters} ${S.get('meters')}.',
        );
        _announceCurrentStep();
      } else {
        _transitLegIndex++;
        _advanceTransitLeg();
      }
    } else {
      _transitPhase = TransitNavPhase.waitForBus;
      final routeNum = leg.routeNumber ?? leg.routeName ?? '';
      final depName = leg.departureStop?.name ?? '';
      final stopsCount = leg.intermediateStops.length + 1;

      onTransitInstruction?.call(
        '${S.get('nav_take_bus')} $routeNum '
        '${S.get('nav_from_stop')} $depName. '
        '${S.get('nav_ride_stops')} $stopsCount.',
      );
      onBusWait?.call(routeNum, depName);
    }
  }

  void confirmBoarded() {
    if (_transitPhase == TransitNavPhase.waitForBus) {
      _transitPhase = TransitNavPhase.riding;
      _transitStopCounter = 0;
      onTransitInstruction?.call(S.get('nav_boarding_confirmed'));
    }
  }

  String _transitStatusSummary() {
    final tr = _transitRoute;
    if (tr == null) return '';

    switch (_transitPhase) {
      case TransitNavPhase.walkToStop:
        if (_route != null) {
          final remaining = _remainingDistance();
          return '${S.get('nav_walking_to_stop')} $remaining ${S.get('meters')}.';
        }
        return S.get('nav_walking_to_stop');
      case TransitNavPhase.waitForBus:
        if (_transitLegIndex < tr.legs.length) {
          final leg = tr.legs[_transitLegIndex];
          return '${S.get('nav_waiting_for')} ${leg.routeNumber ?? ""}.';
        }
        return S.get('nav_waiting');
      case TransitNavPhase.riding:
        if (_transitLegIndex < tr.legs.length) {
          final leg = tr.legs[_transitLegIndex];
          final rem = leg.intermediateStops.length - _transitStopCounter + 1;
          return '${S.get('nav_riding')} ${leg.routeNumber ?? ""}. '
              '${S.get('nav_stops_remaining')} $rem.';
        }
        return S.get('nav_riding');
      case TransitNavPhase.walkFromStop:
        if (_route != null) {
          final remaining = _remainingDistance();
          return '${S.get('nav_walk_to_dest')} $remaining ${S.get('meters')}.';
        }
        return S.get('nav_walk_to_dest');
      case TransitNavPhase.done:
        return S.get('nav_arrived_short');
    }
  }

  String _maneuverToText(Maneuver m) {
    switch (m) {
      case Maneuver.straight:
        return S.get('nav_go_straight');
      case Maneuver.turnLeft:
        return S.get('nav_turn_left');
      case Maneuver.turnRight:
        return S.get('nav_turn_right');
      case Maneuver.slightLeft:
        return S.get('nav_slight_left');
      case Maneuver.slightRight:
        return S.get('nav_slight_right');
      case Maneuver.uTurn:
        return S.get('nav_u_turn');
      case Maneuver.arrive:
        return S.get('nav_arrive');
    }
  }

  String _relDirToText(String dir) {
    switch (dir) {
      case 'straight':
        return S.get('nav_go_straight');
      case 'left':
        return S.get('nav_turn_left');
      case 'right':
        return S.get('nav_turn_right');
      case 'slight_left':
        return S.get('nav_slight_left');
      case 'slight_right':
        return S.get('nav_slight_right');
      case 'behind':
        return S.get('nav_turn_around');
      default:
        return S.get('nav_go_straight');
    }
  }

  void dispose() {
    _gpsSub?.cancel();
  }
}
