#!/usr/bin/env python3
"""Build the self-contained offline reader from the template and sample page."""
import argparse
import base64
import json
from pathlib import Path
from string import Template

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "src"
SAMPLE = ROOT / "examples" / "page"


def render_reader():
    page = json.loads((SAMPLE / "sample.mokuro").read_text(encoding="utf-8"))["pages"][0]
    glosses = json.loads((SAMPLE / "glosses.json").read_text(encoding="utf-8"))
    width, height = page["img_width"], page["img_height"]
    lines = []
    for block in page["blocks"]:
        text = "".join(block["lines"])
        left, top, right, bottom = block["box"]
        # The browser positions hotspots in percentages so they resize with the image.
        lines.append({
            "id": len(lines),
            "raw": text,
            "original": text,
            "translation": glosses[text],
            "box": [100 * left / width, 100 * top / height,
                    100 * (right - left) / width, 100 * (bottom - top) / height],
        })

    template = Template((SOURCE / "reader.html").read_text(encoding="utf-8"))
    return template.substitute(
        reader_css=(SOURCE / "reader.css").read_text(encoding="utf-8"),
        reader_js=(SOURCE / "reader.js").read_text(encoding="utf-8"),
        sample_image=base64.b64encode((SAMPLE / "sample.png").read_bytes()).decode("ascii"),
        sample_width=width,
        sample_height=height,
        # Avoid a literal closing script tag in dialogue or translations.
        sample_lines=json.dumps(lines, ensure_ascii=False).replace("<", "\\u003c"),
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="verify that index.html matches its sources without writing it")
    args = parser.parse_args()
    output = ROOT / "index.html"
    content = render_reader().encode("utf-8")
    if args.check:
        if not output.exists() or output.read_bytes() != content:
            parser.exit(1, "index.html is out of date. Run python3 tools/build_reader.py.\n")
        print("index.html matches its sources.")
    else:
        output.write_bytes(content)
        print("Built index.html.")
