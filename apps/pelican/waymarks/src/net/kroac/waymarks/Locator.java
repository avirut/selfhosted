package net.kroac.waymarks;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import net.minecraft.core.Vec3i;
import net.minecraft.network.protocol.game.ClientboundTrackedWaypointPacket;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.network.ServerGamePacketListenerImpl;
import net.minecraft.world.waypoints.Waypoint;
import net.minecraft.world.waypoints.WaypointStyleAssets;
import org.bukkit.craftbukkit.entity.CraftPlayer;
import org.bukkit.entity.Player;

final class Locator {
    private final Store store;
    private final Looks looks;
    private final Map<UUID, Set<UUID>> shown = new HashMap<>();
    private final Set<UUID> packed = new HashSet<>();

    Locator(Store store, Looks looks) {
        this.store = store;
        this.looks = looks;
    }

    void refresh(Player player) {
        ServerGamePacketListenerImpl connection = ((CraftPlayer) player).getHandle().connection;
        if (connection == null) {
            return;
        }
        Set<UUID> ids = shown.computeIfAbsent(player.getUniqueId(), k -> new HashSet<>());
        for (UUID id : ids) {
            connection.send(ClientboundTrackedWaypointPacket.removeWaypoint(id));
        }
        ids.clear();
        String world = player.getWorld().getKey().asString();
        boolean pack = packed.contains(player.getUniqueId());
        for (Mark mark : store.of(player.getUniqueId())) {
            if (!mark.world().equals(world)) {
                continue;
            }
            connection.send(ClientboundTrackedWaypointPacket.addWaypointPosition(
                    mark.id(), icon(mark, pack), new Vec3i(mark.x(), mark.y(), mark.z())));
            ids.add(mark.id());
        }
    }

    void pack(Player player, boolean loaded) {
        if (loaded) {
            packed.add(player.getUniqueId());
        } else {
            packed.remove(player.getUniqueId());
        }
        refresh(player);
    }

    void clear(Player player) {
        Set<UUID> ids = shown.remove(player.getUniqueId());
        ServerGamePacketListenerImpl connection = ((CraftPlayer) player).getHandle().connection;
        if (ids == null || connection == null) {
            return;
        }
        for (UUID id : ids) {
            connection.send(ClientboundTrackedWaypointPacket.removeWaypoint(id));
        }
    }

    void forget(Player player) {
        shown.remove(player.getUniqueId());
        packed.remove(player.getUniqueId());
    }

    private Waypoint.Icon icon(Mark mark, boolean pack) {
        Waypoint.Icon icon = new Waypoint.Icon();
        icon.style = pack && looks.custom(mark.icon())
                ? ResourceKey.create(WaypointStyleAssets.ROOT_ID, Identifier.fromNamespaceAndPath("waymarks", mark.icon()))
                : WaypointStyleAssets.DEFAULT;
        icon.color = Optional.of(0xFF000000 | mark.color());
        return icon;
    }
}
