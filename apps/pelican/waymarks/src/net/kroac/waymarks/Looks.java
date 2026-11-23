package net.kroac.waymarks;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

final class Looks {
    static final String DOT = "dot";
    static final int WHITE = 0xFFFFFF;
    private static final Pattern HEX = Pattern.compile("#[0-9a-f]{6}");
    private static final Map<String, Integer> COLORS = new LinkedHashMap<>();

    static {
        COLORS.put("white", 0xFFFFFF);
        COLORS.put("gray", 0xAAAAAA);
        COLORS.put("red", 0xFF5555);
        COLORS.put("orange", 0xFFAA00);
        COLORS.put("yellow", 0xFFFF55);
        COLORS.put("lime", 0x55FF55);
        COLORS.put("green", 0x22BB33);
        COLORS.put("cyan", 0x55FFFF);
        COLORS.put("light_blue", 0x55BBFF);
        COLORS.put("blue", 0x5566FF);
        COLORS.put("purple", 0xAA55FF);
        COLORS.put("magenta", 0xFF55FF);
        COLORS.put("pink", 0xFFAACC);
        COLORS.put("brown", 0xAA7744);
    }

    record Look(String icon, int color) {
    }

    private final List<String> icons = new ArrayList<>();

    Looks(List<String> packIcons) {
        icons.add(DOT);
        icons.addAll(packIcons);
    }

    List<String> icons() {
        return icons;
    }

    List<String> colors() {
        return List.copyOf(COLORS.keySet());
    }

    List<String> words() {
        List<String> words = new ArrayList<>(icons);
        words.addAll(COLORS.keySet());
        return words;
    }

    boolean custom(String icon) {
        return !DOT.equals(icon) && icons.contains(icon);
    }

    Look parse(String text, String icon, int color) {
        for (String raw : text.trim().split("\\s+")) {
            if (raw.isEmpty()) {
                continue;
            }
            String word = raw.toLowerCase(Locale.ROOT);
            if (icons.contains(word)) {
                icon = word;
            } else if (COLORS.containsKey(word)) {
                color = COLORS.get(word);
            } else if (HEX.matcher(word).matches()) {
                color = parseHex(word);
            } else {
                throw new IllegalArgumentException(raw);
            }
        }
        return new Look(icon, color);
    }

    static String colorName(int color) {
        for (Map.Entry<String, Integer> e : COLORS.entrySet()) {
            if (e.getValue() == color) {
                return e.getKey();
            }
        }
        return hex(color);
    }

    static String hex(int color) {
        return String.format("#%06x", color & 0xFFFFFF);
    }

    static int parseHex(String text) {
        return Integer.parseInt(text.substring(1), 16) & 0xFFFFFF;
    }
}
