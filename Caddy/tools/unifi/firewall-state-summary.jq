. as $state |

def zone_name($id):
    (
        [
            $state.firewallZones[] |
            select(.id == $id) |
            .name
        ][0]
    ) // "UNKNOWN";

{
    counts: {
        networks: ($state.networks | length),
        firewallZones: ($state.firewallZones | length),
        firewallPolicies: ($state.firewallPolicies | length)
    },
    networks: $state.networks,
    firewallZones: $state.firewallZones,
    relevantPolicies: [
        $state.firewallPolicies[] |
        . as $policy |
        zone_name($policy.source.zoneId) as $source_zone |
        zone_name($policy.destination.zoneId) as $destination_zone |
        select(
            $policy.metadata.origin == "USER_DEFINED" or
            (
                $source_zone == "Internal" and
                $destination_zone == "Internal"
            ) or
            (
                $source_zone == "External" and
                $destination_zone == "Internal"
            )
        ) |
        {
            id: $policy.id,
            name: $policy.name,
            enabled: $policy.enabled,
            index: $policy.index,
            origin: $policy.metadata.origin,
            action: $policy.action,
            sourceZone: $source_zone,
            sourceFilter: ($policy.source.trafficFilter // null),
            destinationZone: $destination_zone,
            destinationFilter: ($policy.destination.trafficFilter // null),
            ipProtocolScope: $policy.ipProtocolScope,
            connectionStateFilter: $policy.connectionStateFilter,
            schedule: $policy.schedule
        }
    ]
}
