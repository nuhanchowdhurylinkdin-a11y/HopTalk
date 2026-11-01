class RouteEntry {
  final String destinationId;
  final String nextHopId;
  final int hopCount;
  final String avatar;
  final String imageByte;

  RouteEntry({
    required this.destinationId,
    required this.nextHopId,
    required this.hopCount,
    required this.avatar,
    required this.imageByte,
  });
}