import 'dart:collection';
import 'dart:typed_data';
import 'kalman_box_tracker.dart';
import 'raw_det.dart';

class Track {
  final int id;
  String label;
  double cx, cy;
  double x1, y1, x2, y2;

  KalmanBoxTracker kalman;

  
  
  
  Float32List? appearance;

  int age = 0;
  int seenCount = 1;

  int nearFrameCount = 0;

  String dist = 'far';
  double distM = -1.0;

  bool approaching = false;

  bool dynamicThreat = false;

  bool fastTrack = false;

  
  
  
  
  final ListQueue<(DateTime, double, double)> centerHist =
      ListQueue<(DateTime, double, double)>();

  
  
  
  double lastAngularVelocity = 0.0;

  
  
  
  
  bool turning = false;

  double avgConf = 0.0;

  int reliableFrames = 0;

  DateTime lastSpoken = DateTime.fromMillisecondsSinceEpoch(0);
  final ListQueue<(DateTime, double)> areaHist =
      ListQueue<(DateTime, double)>();
  final ListQueue<(DateTime, double)> heightHist =
      ListQueue<(DateTime, double)>();
  final ListQueue<String> distHist = ListQueue<String>();

  Track({
    required this.id,
    required this.label,
    required this.cx,
    required this.cy,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.dist,
    required this.distM,
    double initialConf = 0.0,
  }) : avgConf = initialConf,
       kalman = KalmanBoxTracker(
         RawDet(
           label: label,
           x1: x1,
           y1: y1,
           x2: x2,
           y2: y2,
           cx: cx,
           cy: cy,
           conf: initialConf,
           dist: dist,
           distM: distM,
         ),
       );
}
