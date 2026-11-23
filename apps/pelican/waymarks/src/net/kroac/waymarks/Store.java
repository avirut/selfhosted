package net.kroac.waymarks;

import java.io.File;
import java.io.IOException;
import java.util.Collection;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.logging.Level;
import java.util.logging.Logger;
import org.bukkit.configuration.ConfigurationSection;
import org.bukkit.configuration.file.YamlConfiguration;

final class Store {
    private final File file;
    private final Logger logger;
    private final Map<UUID, Map<String, Mark>> marks = new HashMap<>();

    Store(File file, Logger logger) {
        this.file = file;
        this.logger = logger;
    }

    void load() {
        YamlConfiguration yaml = YamlConfiguration.loadConfiguration(file);
        for (String owner : yaml.getKeys(false)) {
            ConfigurationSection section = yaml.getConfigurationSection(owner);
            if (section == null) {
                continue;
            }
            Map<String, Mark> own = new TreeMap<>();
            for (String key : section.getKeys(false)) {
                ConfigurationSection m = section.getConfigurationSection(key);
                if (m == null) {
                    continue;
                }
                own.put(key, new Mark(
                        m.getString("name", key),
                        UUID.fromString(m.getString("id")),
                        m.getString("world"),
                        m.getInt("x"),
                        m.getInt("y"),
                        m.getInt("z"),
                        m.getString("icon", Looks.DOT),
                        Looks.parseHex(m.getString("color", Looks.hex(Looks.WHITE)))));
            }
            marks.put(UUID.fromString(owner), own);
        }
    }

    void save() {
        YamlConfiguration yaml = new YamlConfiguration();
        marks.forEach((owner, own) -> own.forEach((key, m) -> {
            ConfigurationSection s = yaml.createSection(owner + "." + key);
            s.set("name", m.name());
            s.set("id", m.id().toString());
            s.set("world", m.world());
            s.set("x", m.x());
            s.set("y", m.y());
            s.set("z", m.z());
            s.set("icon", m.icon());
            s.set("color", Looks.hex(m.color()));
        }));
        try {
            yaml.save(file);
        } catch (IOException e) {
            logger.log(Level.SEVERE, "Could not save " + file.getName(), e);
        }
    }

    Collection<Mark> of(UUID owner) {
        return marks.getOrDefault(owner, Map.of()).values();
    }

    Mark get(UUID owner, String name) {
        return marks.getOrDefault(owner, Map.of()).get(key(name));
    }

    int count(UUID owner) {
        return marks.getOrDefault(owner, Map.of()).size();
    }

    void put(UUID owner, Mark mark) {
        marks.computeIfAbsent(owner, k -> new TreeMap<>()).put(key(mark.name()), mark);
        save();
    }

    Mark remove(UUID owner, String name) {
        Map<String, Mark> own = marks.get(owner);
        Mark removed = own == null ? null : own.remove(key(name));
        if (removed != null) {
            save();
        }
        return removed;
    }

    private static String key(String name) {
        return name.toLowerCase(Locale.ROOT);
    }
}
