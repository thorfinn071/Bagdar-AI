
import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

SUMMARY_RE = re.compile(
    r"BagdarPerf\[(?P<reason>[^\]]+)\]\s+bridge=(?P<bridge>\w+)\s+"
    r"frames=(?P<frames>\d+)\s+detect=(?P<detect>\d+)\s+"
    r"midas=(?P<midas>\d+)\s+avg_onFrame=(?P<avg_on_frame>\d+(?:\.\d+)?)ms\s+"
    r"window_ms=(?P<window_ms>\d+)\s+"
    r"avg_yolo=(?P<avg_yolo>\d+(?:\.\d+)?)ms\s+"
    r"avg_midas_pre=(?P<avg_midas_pre>\d+(?:\.\d+)?)ms\s+"
    r"avg_midas_infer=(?P<avg_midas_infer>\d+(?:\.\d+)?)ms\s+"
    r"avg_midas_total=(?P<avg_midas_total>\d+(?:\.\d+)?)ms\s+"
    r"native_midas=(?P<native_midas>\d+)/(?P<native_midas_total>\d+)"
    r"\s+\((?P<native_midas_pct>\d+(?:\.\d+)?)%\)\s+"
    r"min_frames=(?P<min_frames>\d+)\s+"
    r"over_budget=(?P<over_budget>\d+)/(?P<over_budget_total>\d+)"
    r"\s+\((?P<over_budget_pct>\d+(?:\.\d+)?)%\)"
)


@dataclass(frozen=True)
class Summary:
    reason: str
    bridge: str
    frames: int
    detect: int
    midas: int
    avg_on_frame: float
    window_ms: int
    avg_yolo: float
    avg_midas_pre: float
    avg_midas_infer: float
    avg_midas_total: float
    native_midas: int
    native_midas_total: int
    native_midas_pct: float
    min_frames: int
    over_budget: int
    over_budget_total: int
    over_budget_pct: float

    @classmethod
    def from_match(cls, match):
        data = match.groupdict()
        return cls(
            reason=data["reason"],
            bridge=data["bridge"],
            frames=int(data["frames"]),
            detect=int(data["detect"]),
            midas=int(data["midas"]),
            avg_on_frame=float(data["avg_on_frame"]),
            window_ms=int(data["window_ms"]),
            avg_yolo=float(data["avg_yolo"]),
            avg_midas_pre=float(data["avg_midas_pre"]),
            avg_midas_infer=float(data["avg_midas_infer"]),
            avg_midas_total=float(data["avg_midas_total"]),
            native_midas=int(data["native_midas"]),
            native_midas_total=int(data["native_midas_total"]),
            native_midas_pct=float(data["native_midas_pct"]),
            min_frames=int(data["min_frames"]),
            over_budget=int(data["over_budget"]),
            over_budget_total=int(data["over_budget_total"]),
            over_budget_pct=float(data["over_budget_pct"]),
        )


def load_text(path):
    if path == "-":
        return sys.stdin.read()
    return Path(path).read_text(encoding="utf-8", errors="replace")


def parse_summaries(text):
    summaries = []
    for line in text.splitlines():
        match = SUMMARY_RE.search(line)
        if match:
            summaries.append(Summary.from_match(match))
    return summaries


def format_summary(summary):
    return (
        f"bridge={summary.bridge:<6} reason={summary.reason:<12} "
        f"frames={summary.frames:<4d} detect={summary.detect:<4d} midas={summary.midas:<4d} "
        f"avg_onFrame={summary.avg_on_frame:.1f}ms avg_midas_pre={summary.avg_midas_pre:.1f}ms "
        f"avg_midas_infer={summary.avg_midas_infer:.1f}ms avg_midas_total={summary.avg_midas_total:.1f}ms "
        f"native_midas={summary.native_midas}/{summary.native_midas_total} ({summary.native_midas_pct:.1f}%) "
        f"over_budget={summary.over_budget}/{summary.over_budget_total} ({summary.over_budget_pct:.1f}%)"
    )


def latest_by_bridge(summaries):
    latest = {}
    for summary in summaries:
        latest[summary.bridge] = summary
    return latest


def delta_pct(new, old):
    if old == 0:
        return 0.0
    return (new - old) / old * 100.0


def main():
    parser = argparse.ArgumentParser(description="Summarize BagdarPerf Android benchmark logs")
    parser.add_argument("path", nargs="?", default="-", help="Path to a log file or - for stdin")
    args = parser.parse_args()

    text = load_text(args.path)
    summaries = parse_summaries(text)

    if not summaries:
        print("No BagdarPerf summaries found.", file=sys.stderr)
        return 1

    print(f"Found {len(summaries)} BagdarPerf summary line(s).")
    for index, summary in enumerate(summaries, start=1):
        print(f"[{index}] {format_summary(summary)}")

    latest = latest_by_bridge(summaries)
    if "dart" in latest and "native" in latest:
        dart = latest["dart"]
        native = latest["native"]
        frame_delta = native.avg_on_frame - dart.avg_on_frame
        budget_delta = native.over_budget_pct - dart.over_budget_pct
        midas_pre_delta = native.avg_midas_pre - dart.avg_midas_pre
        midas_total_delta = native.avg_midas_total - dart.avg_midas_total

        print("Comparison (latest per bridge)")
        print(
            f"  avg_onFrame: dart={dart.avg_on_frame:.1f}ms native={native.avg_on_frame:.1f}ms "
            f"delta={frame_delta:+.1f}ms ({delta_pct(native.avg_on_frame, dart.avg_on_frame):+.1f}%)"
        )
        print(
            f"  over_budget: dart={dart.over_budget_pct:.1f}% native={native.over_budget_pct:.1f}% "
            f"delta={budget_delta:+.1f} pp"
        )
        print(
            f"  avg_midas_pre: dart={dart.avg_midas_pre:.1f}ms native={native.avg_midas_pre:.1f}ms "
            f"delta={midas_pre_delta:+.1f}ms"
        )
        print(
            f"  avg_midas_total: dart={dart.avg_midas_total:.1f}ms native={native.avg_midas_total:.1f}ms "
            f"delta={midas_total_delta:+.1f}ms"
        )
    else:
        available = ", ".join(sorted(latest))
        print(f"Comparison unavailable. Bridges seen: {available}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
