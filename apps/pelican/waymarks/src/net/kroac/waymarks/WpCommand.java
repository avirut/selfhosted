package net.kroac.waymarks;

import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.context.CommandContext;
import com.mojang.brigadier.suggestion.Suggestions;
import com.mojang.brigadier.suggestion.SuggestionsBuilder;
import com.mojang.brigadier.tree.LiteralCommandNode;
import io.papermc.paper.command.brigadier.CommandSourceStack;
import io.papermc.paper.command.brigadier.Commands;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CompletableFuture;
import java.util.regex.Pattern;
import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import net.kyori.adventure.text.format.TextColor;
import org.bukkit.entity.Player;

final class WpCommand {
    private static final Pattern NAME = Pattern.compile("[A-Za-z0-9_-]{1,32}");
    private static final int LIMIT = 50;

    private final Store store;
    private final Locator locator;
    private final Looks looks;

    WpCommand(Store store, Locator locator, Looks looks) {
        this.store = store;
        this.locator = locator;
        this.looks = looks;
    }

    LiteralCommandNode<CommandSourceStack> node() {
        return Commands.literal("wp")
                .requires(s -> s.getExecutor() instanceof Player)
                .executes(this::help)
                .then(Commands.literal("help").executes(this::help))
                .then(Commands.literal("list").executes(this::list))
                .then(Commands.literal("set")
                        .then(Commands.argument("name", StringArgumentType.word())
                                .suggests(this::names)
                                .executes(c -> set(c, ""))
                                .then(Commands.argument("look", StringArgumentType.greedyString())
                                        .suggests(this::looks)
                                        .executes(c -> set(c, StringArgumentType.getString(c, "look"))))))
                .then(Commands.literal("style")
                        .then(Commands.argument("name", StringArgumentType.word())
                                .suggests(this::names)
                                .then(Commands.argument("look", StringArgumentType.greedyString())
                                        .suggests(this::looks)
                                        .executes(this::style))))
                .then(Commands.literal("del")
                        .then(Commands.argument("name", StringArgumentType.word())
                                .suggests(this::names)
                                .executes(this::del)))
                .build();
    }

    private int set(CommandContext<CommandSourceStack> c, String look) {
        Player p = player(c);
        String name = StringArgumentType.getString(c, "name");
        if (!NAME.matcher(name).matches()) {
            return fail(p, "Names can use letters, numbers, - and _ (up to 32).");
        }
        Mark old = store.get(p.getUniqueId(), name);
        if (old == null && store.count(p.getUniqueId()) >= LIMIT) {
            return fail(p, "You already have " + LIMIT + " waypoints. Delete one first.");
        }
        Looks.Look parsed;
        try {
            parsed = looks.parse(look, old == null ? Looks.DOT : old.icon(), old == null ? Looks.WHITE : old.color());
        } catch (IllegalArgumentException e) {
            return fail(p, "Unknown icon or color: " + e.getMessage() + ". Try /wp help.");
        }
        Mark mark = old == null
                ? Mark.at(name, p.getLocation(), parsed.icon(), parsed.color())
                : old.movedTo(p.getLocation()).styled(parsed.icon(), parsed.color());
        store.put(p.getUniqueId(), mark);
        locator.refresh(p);
        p.sendMessage(Component.text(old == null ? "Set " : "Moved ", NamedTextColor.GRAY).append(describe(mark)));
        return 1;
    }

    private int style(CommandContext<CommandSourceStack> c) {
        Player p = player(c);
        Mark old = store.get(p.getUniqueId(), StringArgumentType.getString(c, "name"));
        if (old == null) {
            return fail(p, "No waypoint called " + StringArgumentType.getString(c, "name") + ".");
        }
        Looks.Look parsed;
        try {
            parsed = looks.parse(StringArgumentType.getString(c, "look"), old.icon(), old.color());
        } catch (IllegalArgumentException e) {
            return fail(p, "Unknown icon or color: " + e.getMessage() + ". Try /wp help.");
        }
        Mark mark = old.styled(parsed.icon(), parsed.color());
        store.put(p.getUniqueId(), mark);
        locator.refresh(p);
        p.sendMessage(Component.text("Updated ", NamedTextColor.GRAY).append(describe(mark)));
        return 1;
    }

    private int del(CommandContext<CommandSourceStack> c) {
        Player p = player(c);
        Mark removed = store.remove(p.getUniqueId(), StringArgumentType.getString(c, "name"));
        if (removed == null) {
            return fail(p, "No waypoint called " + StringArgumentType.getString(c, "name") + ".");
        }
        locator.refresh(p);
        p.sendMessage(Component.text("Deleted " + removed.name() + ".", NamedTextColor.GRAY));
        return 1;
    }

    private int list(CommandContext<CommandSourceStack> c) {
        Player p = player(c);
        List<Mark> marks = new ArrayList<>(store.of(p.getUniqueId()));
        if (marks.isEmpty()) {
            p.sendMessage(Component.text("No waypoints yet. /wp set <name> marks where you stand.", NamedTextColor.GRAY));
            return 1;
        }
        marks.sort(Comparator.comparing(m -> m.name().toLowerCase(Locale.ROOT)));
        p.sendMessage(Component.text("Your waypoints (" + marks.size() + "):", NamedTextColor.GRAY));
        for (Mark m : marks) {
            p.sendMessage(Component.text(" ").append(describe(m))
                    .append(Component.text("  " + dimension(m.world()) + " " + m.x() + " " + m.y() + " " + m.z(), NamedTextColor.DARK_GRAY)));
        }
        return 1;
    }

    private int help(CommandContext<CommandSourceStack> c) {
        Player p = player(c);
        p.sendMessage(Component.text("Waypoints show on your locator bar in the same dimension.", NamedTextColor.GRAY));
        line(p, "/wp set <name> [icon] [color]", "mark where you stand, or move it here");
        line(p, "/wp style <name> <icon/color>", "change its look");
        line(p, "/wp del <name>", "delete it");
        line(p, "/wp list", "list yours");
        p.sendMessage(Component.text("Icons: " + String.join(", ", looks.icons()), NamedTextColor.GRAY));
        p.sendMessage(Component.text("Colors: " + String.join(", ", looks.colors()) + ", or #rrggbb", NamedTextColor.GRAY));
        return 1;
    }

    private static void line(Player p, String usage, String what) {
        p.sendMessage(Component.text(" " + usage, NamedTextColor.WHITE).append(Component.text("  " + what, NamedTextColor.DARK_GRAY)));
    }

    private static Component describe(Mark m) {
        return Component.text("■ " + m.name(), TextColor.color(m.color()))
                .append(Component.text(" (" + m.icon() + ", " + Looks.colorName(m.color()) + ")", NamedTextColor.GRAY));
    }

    private static String dimension(String world) {
        int colon = world.indexOf(':');
        return colon >= 0 ? world.substring(colon + 1) : world;
    }

    private CompletableFuture<Suggestions> names(CommandContext<CommandSourceStack> c, SuggestionsBuilder b) {
        if (c.getSource().getExecutor() instanceof Player p) {
            String typed = b.getRemainingLowerCase();
            for (Mark m : store.of(p.getUniqueId())) {
                if (m.name().toLowerCase(Locale.ROOT).startsWith(typed)) {
                    b.suggest(m.name());
                }
            }
        }
        return b.buildFuture();
    }

    private CompletableFuture<Suggestions> looks(CommandContext<CommandSourceStack> c, SuggestionsBuilder b) {
        String typed = b.getRemaining();
        int cut = typed.lastIndexOf(' ') + 1;
        String last = typed.substring(cut).toLowerCase(Locale.ROOT);
        SuggestionsBuilder word = b.createOffset(b.getStart() + cut);
        for (String s : looks.words()) {
            if (s.startsWith(last)) {
                word.suggest(s);
            }
        }
        return word.buildFuture();
    }

    private static Player player(CommandContext<CommandSourceStack> c) {
        return (Player) c.getSource().getExecutor();
    }

    private static int fail(Player p, String message) {
        p.sendMessage(Component.text(message, NamedTextColor.RED));
        return 0;
    }
}
