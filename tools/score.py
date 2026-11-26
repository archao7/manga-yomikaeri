"""Score the published Japanese OCR outputs using only the Python standard library."""

import argparse
from collections import Counter
import json
from pathlib import Path
import sys


DATA = Path(__file__).resolve().parent.parent / "evaluation"
VARIANTS = {"A": "preview.mokuro", "B": "sample.mokuro"}


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"无法读取 {path}：{error}") from error


def dialogue_list(value):
    return (isinstance(value, list) and
            all(isinstance(text, str) and text for text in value))


def read_dialogues(path):
    data = read_json(path)
    try:
        pages = data["pages"]
        if len(pages) != 1:
            raise ValueError(f"{path} 必须只含一页")
        blocks = pages[0]["blocks"]
        if not isinstance(blocks, list):
            raise ValueError(f"{path} 的 blocks 必须是数组")
        dialogues = []
        for block in blocks:
            lines = block["lines"]
            if not dialogue_list(lines) or not lines:
                raise ValueError(f"{path} 含无效的对白标注")
            dialogues.append("".join(lines))
        return dialogues
    except (KeyError, TypeError, IndexError) as error:
        raise ValueError(f"{path} 缺少可读的页面或对白标注") from error


def evaluate(folder):
    truth = read_json(folder / "ground-truth.json")
    report = read_json(folder / "results.json")
    if not isinstance(truth, dict) or not truth:
        raise ValueError("ground-truth.json 需要包含场景和原文")
    pages = report["pages"]
    if not isinstance(pages, list):
        raise ValueError("results.json 的 pages 必须是数组")
    total = 0
    scores = Counter()
    seen_scenes = set()
    seen_folders = set()
    for page in pages:
        scene, number = page["scenario"], page["page"]
        if scene in seen_scenes or scene not in truth:
            raise ValueError(f"场景重复或不存在：{scene}")
        if type(number) is not int or number < 1:
            raise ValueError(f"{scene} 的页码无效")
        name = f"page-{number}"
        if name in seen_folders:
            raise ValueError(f"{name} 出现多次")
        seen_scenes.add(scene)
        seen_folders.add(name)

        expected = truth[scene]
        if not dialogue_list(expected) or not expected or expected != page["reference"]:
            raise ValueError(f"{scene} 的原文缺失或与报告不一致")
        hits = {}
        for variant, filename in VARIANTS.items():
            recognized = read_dialogues(folder / name / filename)
            # A repeated OCR hit can cover at most one copy of each expected sentence.
            matched = sum((Counter(expected) & Counter(recognized)).values())
            if matched != page[variant]["matched"] or recognized != page[variant]["recognized"]:
                raise ValueError(f"{name} {variant} 复算结果或识别文本与报告不一致")
            hits[variant] = matched
            scores[variant] += matched
        total += len(expected)
        print(f"{number}. {scene}   缩略图 {hits['A']}/{len(expected)}   原图 {hits['B']}/{len(expected)}")

    missing = set(truth) - seen_scenes
    if missing:
        raise ValueError("报告遗漏场景：" + "、".join(sorted(missing)))
    folders = {path.name for path in folder.glob("page-*") if path.is_dir()}
    if seen_folders != folders:
        raise ValueError("报告页码与样本目录不一致：" + "、".join(sorted(seen_folders ^ folders)))
    if total != report["reference_count"] or dict(scores) != report["summary"]:
        raise ValueError("复算总数与 results.json 的汇总不一致")
    print(f"合计 {len(pages)} 页 / {total} 句：缩略图 {scores['A']}/{total}，原图 {scores['B']}/{total}。")


def main():
    parser = argparse.ArgumentParser(description="从已发布的 OCR 标注逐页复算整句匹配数")
    parser.add_argument("folder", type=Path, nargs="?", default=DATA, help="评测目录（默认使用仓库内 evaluation）")
    try:
        evaluate(parser.parse_args().folder)
    except (ValueError, KeyError, TypeError) as error:
        print(f"评测数据校验失败：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
