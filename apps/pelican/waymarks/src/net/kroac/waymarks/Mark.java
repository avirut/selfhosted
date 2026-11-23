package net.kroac.waymarks;

import java.util.UUID;
import org.bukkit.Location;

record Mark(String name, UUID id, String world, int x, int y, int z, String icon, int color) {
    static Mark at(String name, Location at, String icon, int color) {
        return new Mark(name, UUID.randomUUID(), at.getWorld().getKey().asString(), at.getBlockX(), at.getBlockY(), at.getBlockZ(), icon, color);
    }

    Mark movedTo(Location at) {
        return new Mark(name, id, at.getWorld().getKey().asString(), at.getBlockX(), at.getBlockY(), at.getBlockZ(), icon, color);
    }

    Mark styled(String icon, int color) {
        return new Mark(name, id, world, x, y, z, icon, color);
    }
}
