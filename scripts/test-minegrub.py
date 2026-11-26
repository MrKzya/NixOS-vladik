"""Check the bounded menu layout and scrolling without booting GRUB."""
import re
import sys
from pathlib import Path

theme = Path(sys.argv[1]).read_text()
assert theme.count("+ boot_menu") == 1
menu = re.search(r"\+ boot_menu\s*\{([^}]+)\}", theme)[1]
options = dict(re.findall(r"^\s*(\w+)\s*=\s*(\S+)", menu, re.M))
assert options["scrollbar"] == "true"
assert "scrollbar_frame" in options and "scrollbar_thumb" in options

item = int(options["item_height"])
spacing = int(options["item_spacing"])
bar_top = int(re.search(r"top\s*=\s*(\d+)%\s*\n\s*file\s*=\s*\"static_bar.png\"", theme)[1])
for pixels in (600, 720, 768, 800, 1080, 1600):
    top = pixels * int(options["top"].rstrip("%")) // 100
    height = pixels * int(options["height"].rstrip("%")) // 100
    assert 195 + pixels // 100 <= top
    assert top + height <= pixels * bar_top // 100
    visible = (height + spacing) // (item + spacing)
    assert visible > 0
    for generations in (1, 4, 5, 10, 20):
        for selection in range(generations):
            start = max(0, selection - visible + 1)
            end = min(generations, start + visible)
            assert start <= selection < end
            rows = [(top + i * (item + spacing), top + i * (item + spacing) + item)
                    for i in range(end - start)]
            assert all(a[1] <= b[0] for a, b in zip(rows, rows[1:]))
            assert rows[-1][1] <= top + height
print("Minegrub layout bounds for 1, 4, 5, 10 and 20 entries passed.")
