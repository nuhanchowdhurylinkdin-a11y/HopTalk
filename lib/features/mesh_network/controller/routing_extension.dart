part of 'mesh_network_controller.dart';

extension MeshRouting on MeshNetworkController {
  void _addDirectNeighbor(String endpointId, String userId) {
    final bool isNewUser = !routingTable.containsKey(userId);
    routingTable[userId] = _newRoute(
      userId,
      endpointId,
      1,
      hasEsp32: routingTable[userId]?.hasEsp32 ?? false,
    );
    if (isNewUser) _queueEsp32UserIdDelta(userId, add: true);
  }

  RouteEntry _newRoute(
    String destId,
    String nextHopId,
    int hopCount, {
    bool hasEsp32 = false,
  }) {
    final Map<String, dynamic>? profile = knownProfiles[destId];
    return RouteEntry(
      destinationId: destId,
      nextHopId: nextHopId,
      hopCount: hopCount,
      avatar: (profile?['avatar'] as String?) ?? '',
      imageByte: (profile?['image'] as String?) ?? '',
      hasEsp32: hasEsp32,
    );
  }

  void _applyProfileToRoutes(String userId) {
    final RouteEntry? entry = routingTable[userId];
    if (entry == null) return;
    routingTable[userId] = _newRoute(
      userId,
      entry.nextHopId,
      entry.hopCount,
      hasEsp32: entry.hasEsp32,
    );
  }

  void _sendRoutingTableTo(String endpointId) {
    final List<Map<String, dynamic>> routesList = [];

    routingTable.forEach((desId, entry) {
      if (entry.nextHopId == endpointId) return;
      routesList.add({
        "destinationId": entry.destinationId,
        "hopCount": entry.hopCount,
        "gw": entry.hasEsp32,
      });
    });

    Map<String, dynamic> routingPacket = {
      "type": "ROUTING_UPDATE",
      "senderUserId": _currentUserId,
      "routes": routesList,
    };

    Uint8List bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(routingPacket)),
    );

    _sendBytes(endpointId, bytes);
  }

  void _broadcastRoutingTable({String? exceptEndpointId}) {
    for (final endpointId in connectedEndpoints.keys.toList()) {
      if (endpointId != exceptEndpointId) {
        _sendRoutingTableTo(endpointId);
      }
    }
  }

  void _processRoutingUpdate(
    String senderEndpointId,
    Map<String, dynamic> packet,
  ) {
    final routes = packet['routes'];
    if (routes is! List) return;

    bool isTableChanged = false;
    final Set<String> addedUserIds = {};
    final Set<String> removedUserIds = {};
    final Set<String> advertisedDestinations = {};

    for (final route in routes) {
      if (route is! Map) continue;

      final destId = route['destinationId'];
      final incomingHops = route['hopCount'];
      if (destId is! String || incomingHops is! int) continue;
      if (destId == _currentUserId) continue;

      final bool incomingGw = route['gw'] == true;

      final int calculatedHops = incomingHops + 1;
      if (calculatedHops > _maxHops) continue;

      advertisedDestinations.add(destId);

      final RouteEntry? existing = routingTable[destId];
      bool shouldReplace;
      if (existing == null) {
        shouldReplace = true;
      } else if (existing.nextHopId == senderEndpointId) {
        shouldReplace =
            existing.hopCount != calculatedHops ||
            existing.hasEsp32 != incomingGw;
      } else {
        shouldReplace = existing.hopCount > calculatedHops;
      }

      if (shouldReplace) {
        if (existing == null) addedUserIds.add(destId);
        if (existing == null || existing.hasEsp32 != incomingGw) {
          _log(
            "Route ${_shortId(destId)} gateway=$incomingGw hops=$calculatedHops",
          );
        }
        routingTable[destId] = _newRoute(
          destId,
          senderEndpointId,
          calculatedHops,
          hasEsp32: incomingGw,
        );
        isTableChanged = true;
      }
    }

    final List<String> staleDestinations = routingTable.entries
        .where(
          (e) =>
              e.value.nextHopId == senderEndpointId &&
              !advertisedDestinations.contains(e.key),
        )
        .map((e) => e.key)
        .toList();

    for (final destId in staleDestinations) {
      routingTable.remove(destId);
      removedUserIds.add(destId);
      isTableChanged = true;
    }

    if (isTableChanged) {
      _broadcastRoutingTable(exceptEndpointId: senderEndpointId);
      for (final userId in addedUserIds) {
        _queueEsp32UserIdDelta(userId, add: true);
      }
      for (final userId in removedUserIds) {
        _queueEsp32UserIdDelta(userId, add: false);
      }
      update();
    }
  }

  bool _removeRoutesVia(String endpointId) {
    final List<String> destinations = routingTable.entries
        .where((e) => e.value.nextHopId == endpointId)
        .map((e) => e.key)
        .toList();

    for (final destId in destinations) {
      routingTable.remove(destId);
      _queueEsp32UserIdDelta(destId, add: false);
    }
    return destinations.isNotEmpty;
  }

  void _startRouteRefresh() {
    _routeRefreshTimer?.cancel();
    _routeRefreshTimer = Timer.periodic(
      Duration(seconds: _routeRefreshSeconds),
      (_) => _broadcastRoutingTable(),
    );
  }

  RouteEntry? bestGateway() {
    RouteEntry? best;
    for (final entry in routingTable.values) {
      if (!entry.hasEsp32) continue;
      if (best == null || entry.hopCount < best.hopCount) best = entry;
    }
    return best;
  }

  List<RouteEntry> get gateways {
    final List<RouteEntry> list = routingTable.values
        .where((e) => e.hasEsp32)
        .toList();
    list.sort((a, b) => a.hopCount.compareTo(b.hopCount));
    return list;
  }

  List<RouteEntry> get reachableRoutes {
    final List<RouteEntry> list = routingTable.values
        .where((e) => e.nextHopId != 'SELF')
        .toList();

    list.sort((a, b) {
      final int byHops = a.hopCount.compareTo(b.hopCount);
      if (byHops != 0) return byHops;
      return displayNameOf(a.destinationId)
          .compareTo(displayNameOf(b.destinationId));
    });

    return list;
  }

  String displayNameOf(String userId) {
    final String? name = knownUsers[userId];
    if (name != null && name.isNotEmpty) return name;
    return userId.length > 6 ? userId.substring(0, 6) : userId;
  }
}
