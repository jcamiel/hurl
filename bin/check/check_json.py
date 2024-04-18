#!/usr/bin/env python3
import json
import sys
from dataclasses import dataclass
from datetime import datetime


@dataclass
class Timings:
    begin_call: datetime
    end_call: datetime

    @staticmethod
    def from_json(info) -> "Timings":
        begin_call = info["begin_call"]
        begin_call = datetime.fromisoformat(begin_call)
        end_call = info["end_call"]
        end_call = datetime.fromisoformat(end_call)
        return Timings(begin_call=begin_call, end_call=end_call)


@dataclass
class Call:
    timings: Timings

    @staticmethod
    def from_json(info) -> "Call":
        timings = Timings.from_json(info["timings"])
        return Call(timings=timings)


@dataclass
class Entry:
    index: int
    line: int
    time: int
    calls: list[Call]

    @staticmethod
    def from_json(info) -> "Entry":
        index = info["index"]
        line = info["line"]
        time = info["time"]
        calls = [Call.from_json(c) for c in info["calls"]]
        return Entry(index=index, line=line, time=time, calls=calls)


@dataclass
class HurlResult:
    filename: str
    success: bool
    time: int
    entries: list[Entry]

    @staticmethod
    def from_str(info: str) -> "HurlResult":
        result = json.loads(info)
        filename = result["filename"]
        success = result["success"]
        time = result["time"]
        entries = [Entry.from_json(e) for e in result["entries"]]
        return HurlResult(
            filename=filename, success=success, time=time, entries=entries
        )


def main(data: str):
    for line in data.splitlines():
        result = HurlResult.from_str(line)
        print(f"{result}")


if __name__ == "__main__":
    main(sys.stdin.read())
