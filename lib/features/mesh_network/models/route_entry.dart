class RouteEntry {
  final String destinationId;
  final String nextHopId;
  final int hopCount;
  final String avatar;
  final String imageByte;
  final bool hasEsp32;

  const RouteEntry({
    required this.destinationId,
    required this.nextHopId,
    required this.hopCount,
    this.avatar = '',
    this.imageByte = '',
    this.hasEsp32 = false,
  });
}