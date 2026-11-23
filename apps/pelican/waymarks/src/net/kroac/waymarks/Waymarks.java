package net.kroac.waymarks;

import io.papermc.paper.plugin.lifecycle.event.types.LifecycleEvents;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;
import net.kyori.adventure.resource.ResourcePackInfo;
import net.kyori.adventure.resource.ResourcePackRequest;
import net.kyori.adventure.text.Component;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerChangedWorldEvent;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.event.player.PlayerResourcePackStatusEvent;
import org.bukkit.event.player.PlayerRespawnEvent;
import org.bukkit.plugin.java.JavaPlugin;

public final class Waymarks extends JavaPlugin implements Listener {
    private Locator locator;
    private ResourcePackRequest pack;
    private UUID packId;

    @Override
    public void onEnable() {
        saveDefaultConfig();
        Looks looks = new Looks(icons());
        Store store = new Store(new File(getDataFolder(), "marks.yml"), getLogger());
        store.load();
        locator = new Locator(store, looks);
        String url = getConfig().getString("pack-url", "");
        String sha1 = getConfig().getString("pack-sha1", "");
        if (!url.isBlank()) {
            packId = UUID.nameUUIDFromBytes(("waymarks:" + url + ":" + sha1).getBytes(StandardCharsets.UTF_8));
            pack = ResourcePackRequest.resourcePackRequest()
                    .packs(ResourcePackInfo.resourcePackInfo(packId, URI.create(url), sha1))
                    .required(false)
                    .replace(false)
                    .prompt(Component.text("Icons for /wp waypoints"))
                    .build();
        }
        getServer().getPluginManager().registerEvents(this, this);
        WpCommand command = new WpCommand(store, locator, looks);
        getLifecycleManager().registerEventHandler(LifecycleEvents.COMMANDS,
                event -> event.registrar().register(command.node(), "Waypoints on the locator bar", List.of("waymark", "waymarks")));
        getServer().getOnlinePlayers().forEach(locator::refresh);
    }

    @Override
    public void onDisable() {
        if (locator != null) {
            getServer().getOnlinePlayers().forEach(locator::clear);
        }
    }

    private List<String> icons() {
        try (InputStream in = getResource("icons.txt")) {
            if (in == null) {
                return List.of();
            }
            return new String(in.readAllBytes(), StandardCharsets.UTF_8).lines().filter(s -> !s.isBlank()).toList();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        if (pack != null) {
            event.getPlayer().sendResourcePacks(pack);
        }
        locator.refresh(event.getPlayer());
    }

    @EventHandler
    public void onWorld(PlayerChangedWorldEvent event) {
        locator.refresh(event.getPlayer());
    }

    @EventHandler
    public void onRespawn(PlayerRespawnEvent event) {
        Player player = event.getPlayer();
        getServer().getScheduler().runTask(this, () -> {
            if (player.isOnline()) {
                locator.refresh(player);
            }
        });
    }

    @EventHandler
    public void onPack(PlayerResourcePackStatusEvent event) {
        if (packId == null || !packId.equals(event.getID())) {
            return;
        }
        switch (event.getStatus()) {
            case SUCCESSFULLY_LOADED -> locator.pack(event.getPlayer(), true);
            case DECLINED, FAILED_DOWNLOAD, INVALID_URL, FAILED_RELOAD, DISCARDED -> locator.pack(event.getPlayer(), false);
            default -> {
            }
        }
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        locator.forget(event.getPlayer());
    }
}
