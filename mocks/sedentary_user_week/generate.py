#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pibo mock 数据生成器 —— 不爱动用户一周 HealthKit 数据（对照组）。

与 active_user_week 同 schema，刻意做成反面画像，用来压测 Pibo 的
衰减 / 死亡触发 / 久坐提醒逻辑。

人物画像：
  小默，35 岁，久坐办公族，几乎不运动，作息不规律。
  静息心率偏高 ~73bpm，HRV 偏低 ~30ms，心肺适能低（VO2max ~31）。
  不总是戴表睡觉 —— 一周里有 2 晚没戴（=没有睡眠数据，真实情况）。
  一周（2026-06-01 周一 ~ 06-07 周日）：
    工作日基本零运动，久坐；周六勉强散步一次，周日完全宅家。
    系统给出 lowCardioFitnessEvent（心肺适能偏低）+ 偶发 highHeartRateEvent。

输出：sedentary_user_week.jsonl
运行：python3 generate.py
"""

import json
import random
from datetime import datetime, timedelta, timezone

random.seed(20260602)

TZ = timezone(timedelta(hours=8))
WATCH = "Apple Watch SE"  # 老一些的机型：无血氧/无手腕温度传感器

records = []


def iso(dt):
    return dt.isoformat(timespec="seconds")


def add(**kw):
    records.append(kw)


def quantity(qtype, value, unit, start, end=None, tier="A", **extra):
    rec = dict(type=qtype, sampleClass="quantity", value=value, unit=unit,
               start=iso(start), end=iso(end or start), source=WATCH, tier=tier)
    rec.update(extra)
    add(**rec)


def category(ctype, value, start, end, tier="A", **extra):
    rec = dict(type=ctype, sampleClass="category", value=value,
               start=iso(start), end=iso(end), source=WATCH, tier=tier)
    rec.update(extra)
    add(**rec)


def day_at(base, h, m=0):
    return base.replace(hour=h, minute=m, second=0, microsecond=0)


def parse_date(s):
    y, m, d = map(int, s.split("-"))
    return datetime(y, m, d, tzinfo=TZ)


# ---------------------------------------------------------------------------
# 每日计划 —— 久坐画像
#   workout=None 表示当天没有任何主动运动
#   sleep=None   表示当晚没戴表（拿不到睡眠 / 夜间生理数据）
# ---------------------------------------------------------------------------
PLAN = [
    {
        "label": "周一·久坐", "date": "2026-06-01", "workout": None,
        "steps": 2840, "active_kcal": 180, "exercise_min": 3,
        "stand_h": 5, "flights": 1, "rhr": 72, "whr_avg": 114,
        "hrv": 33, "vo2": None, "mindful": None,
        "sleep_start": ("2026-06-01", 1, 10), "sleep_dur_h": 5.6,
        "resp_rate": 16.4, "wrist_temp_dev": None,  # SE 无手腕温度
        "events": [],
    },
    {
        "label": "周二·久坐", "date": "2026-06-02", "workout": None,
        "steps": 1960, "active_kcal": 150, "exercise_min": 1,
        "stand_h": 4, "flights": 0, "rhr": 74, "whr_avg": 117,
        "hrv": 29, "vo2": None, "mindful": None,
        "sleep_start": None, "sleep_dur_h": 0,       # 没戴表睡
        "resp_rate": None, "wrist_temp_dev": None,
        "events": [("highHeartRateEvent", 15, 30)],  # 久坐时一次心率偏高
    },
    {
        "label": "周三·久坐", "date": "2026-06-03", "workout": None,
        "steps": 3220, "active_kcal": 205, "exercise_min": 4,
        "stand_h": 6, "flights": 2, "rhr": 73, "whr_avg": 112,
        "hrv": 35, "vo2": 31.4, "mindful": None,
        "sleep_start": ("2026-06-03", 0, 40), "sleep_dur_h": 6.2,
        "resp_rate": 15.8, "wrist_temp_dev": None,
        "events": [("lowCardioFitnessEvent", 12, 0)],  # 心肺适能偏低
    },
    {
        "label": "周四·久坐", "date": "2026-06-04", "workout": None,
        "steps": 1480, "active_kcal": 132, "exercise_min": 0,
        "stand_h": 4, "flights": 0, "rhr": 75, "whr_avg": 119,
        "hrv": 27, "vo2": None, "mindful": None,
        "sleep_start": ("2026-06-04", 1, 50), "sleep_dur_h": 5.1,
        "resp_rate": 16.9, "wrist_temp_dev": None,
        "events": [],
    },
    {
        "label": "周五·久坐", "date": "2026-06-05", "workout": None,
        "steps": 2610, "active_kcal": 168, "exercise_min": 2,
        "stand_h": 5, "flights": 1, "rhr": 73, "whr_avg": 115,
        "hrv": 31, "vo2": None,
        "mindful": [(23, 20, 1)],  # App 提醒，敷衍 1 分钟
        "sleep_start": None, "sleep_dur_h": 0,       # 又没戴表睡
        "resp_rate": None, "wrist_temp_dev": None,
        "events": [],
    },
    {
        "label": "周六·散步", "date": "2026-06-06",
        "workout": {
            "activityType": "walking", "startH": 17, "startM": 30, "durMin": 22,
            "distance_m": 1600, "kcal": 95, "avgHR": 108, "maxHR": 124,
            "indoor": False, "weather": "阴 26℃", "elevation_m": 6,
            "avgPace": "13:45/km", "recoveryHR": None,
        },
        "steps": 5400, "active_kcal": 260, "exercise_min": 12,
        "stand_h": 7, "flights": 2, "rhr": 72, "whr_avg": 111,
        "hrv": 36, "vo2": None, "mindful": None,
        "sleep_start": ("2026-06-06", 0, 30), "sleep_dur_h": 7.0,
        "resp_rate": 15.4, "wrist_temp_dev": None,
        "events": [],
    },
    {
        "label": "周日·宅家", "date": "2026-06-07", "workout": None,
        "steps": 1120, "active_kcal": 118, "exercise_min": 0,
        "stand_h": 3, "flights": 0, "rhr": 74, "whr_avg": 118,
        "hrv": 28, "vo2": None, "mindful": None,
        "sleep_start": ("2026-06-07", 2, 20), "sleep_dur_h": 6.6,
        "resp_rate": 16.1, "wrist_temp_dev": None,
        "events": [("highHeartRateEvent", 21, 10)],
    },
]


# ---------------------------------------------------------------------------
# 逐日生成
# ---------------------------------------------------------------------------
for day in PLAN:
    base = parse_date(day["date"])
    midnight = day_at(base, 0, 0)
    end_of_day = day_at(base, 23, 59)

    # --- 睡眠（可能整晚缺失：没戴表） -----------------------------------
    if day["sleep_start"]:
        sy, sh, sm = day["sleep_start"]
        sd = datetime(*map(int, sy.split("-")), sh, sm, tzinfo=TZ)
        total_sleep = timedelta(hours=day["sleep_dur_h"])
        # 久坐 + 压力大：碎觉，清醒占比高，深睡/REM 偏少
        sleep_end = sd + total_sleep + timedelta(minutes=random.randint(25, 55))
        category("sleepAnalysis", "inBed", sd, sleep_end, tier="B", note="整段卧床")
        stages = [
            ("asleepCore", 0.34), ("awake", 0.06), ("asleepDeep", 0.06),
            ("asleepCore", 0.22), ("asleepREM", 0.08), ("awake", 0.05),
            ("asleepCore", 0.19),
        ]
        cur = sd
        for stage, frac in stages:
            nxt = cur + total_sleep * frac
            category("sleepAnalysis", stage, cur, nxt, tier="B")
            cur = nxt
        mid_sleep = sd + total_sleep / 2
        if day["resp_rate"]:
            quantity("respiratoryRate", day["resp_rate"], "count/min", mid_sleep,
                     tier="C", context="sleep")
        # SE 无血氧/手腕温度传感器 → 不产出这两类（真实型号差异）
    # else: 当晚没戴表，完全没有睡眠/夜间数据

    # --- 当日累计型 -----------------------------------------------------
    quantity("stepCount", day["steps"], "count", midnight, end_of_day)
    quantity("distanceWalkingRunning", round(day["steps"] * 0.00069, 2), "km",
             midnight, end_of_day)
    quantity("activeEnergyBurned", day["active_kcal"], "kcal", midnight, end_of_day)
    quantity("basalEnergyBurned", random.randint(1480, 1560), "kcal",
             midnight, end_of_day)
    quantity("appleExerciseTime", day["exercise_min"], "min", midnight, end_of_day)
    quantity("appleStandTime", day["stand_h"] * 60 - random.randint(10, 50), "min",
             midnight, end_of_day)
    quantity("flightsClimbed", day["flights"], "count", midnight, end_of_day)
    quantity("appleMoveTime", day["exercise_min"] + random.randint(5, 20), "min",
             midnight, end_of_day)

    # 站立小时（久坐 → 达标小时很少，且集中在工作间隙）
    stood_hours = sorted(random.sample(range(9, 22), day["stand_h"]))
    for h in stood_hours:
        category("appleStandHour", "stood", day_at(base, h, 0), day_at(base, h, 1))
    # 其余整点标记 idle（久坐特征，方便驱动「站立提醒」类玩法）
    for h in range(9, 22):
        if h not in stood_hours:
            category("appleStandHour", "idle", day_at(base, h, 0),
                     day_at(base, h, 1), note="未起身")

    # --- 心率类 ---------------------------------------------------------
    quantity("restingHeartRate", day["rhr"], "count/min", day_at(base, 7, 0))
    quantity("walkingHeartRateAverage", day["whr_avg"], "count/min",
             day_at(base, 18, 0))
    quantity("heartRateVariabilitySDNN", day["hrv"], "ms", day_at(base, 7, 5),
             context="morning")
    if day["vo2"]:
        quantity("vo2Max", day["vo2"], "mL/min·kg", day_at(base, 12, 0), tier="B",
                 note="偏低")

    # 全天散点心率：久坐基线偏高、波动小
    for h, m, v in [(4, 0, day["rhr"] - 3), (8, 0, day["rhr"] + 6),
                    (11, 0, day["rhr"] + 12), (14, 0, day["rhr"] + 9),
                    (17, 0, day["rhr"] + 14), (21, 0, day["rhr"] + 8),
                    (23, 30, day["rhr"] + 2)]:
        quantity("heartRate", v + random.randint(-3, 3), "count/min",
                 day_at(base, h, m))

    # --- 健康事件（久坐/亚健康信号） -----------------------------------
    for (etype, eh, em) in day.get("events", []):
        t = day_at(base, eh, em)
        category(etype, "event", t, t + timedelta(minutes=1), tier="C")
        if etype == "highHeartRateEvent":
            quantity("heartRate", random.randint(118, 132), "count/min", t,
                     note="静息时偏高")

    # --- 敷衍冥想（若有） ----------------------------------------------
    for (mh, mm, mdur) in (day["mindful"] or []):
        ms = day_at(base, mh, mm)
        category("mindfulSession", "session", ms, ms + timedelta(minutes=mdur),
                 tier="B")

    # --- 环境 / 日照（室内为主 → 日照很低） ----------------------------
    quantity("environmentalAudioExposure", random.randint(52, 66), "dBASPL",
             day_at(base, 15, 0))
    quantity("timeInDaylight", random.randint(6, 35), "min", midnight, end_of_day)

    # --- Workout（多数天没有） -----------------------------------------
    w = day["workout"]
    if w:
        w_start = day_at(base, w["startH"], w["startM"])
        w_end = w_start + timedelta(minutes=w["durMin"])
        quantity("timeInDaylight", w["durMin"], "min", w_start, w_end,
                 context="outdoor-workout")
        workout = dict(
            type="workout", sampleClass="workout", activityType=w["activityType"],
            start=iso(w_start), end=iso(w_end), durationSec=w["durMin"] * 60,
            totalDistance_m=w["distance_m"], totalEnergyBurned_kcal=w["kcal"],
            avgHeartRate_bpm=w["avgHR"], maxHeartRate_bpm=w["maxHR"],
            source=WATCH, tier="B",
            metadata={"indoor": w["indoor"], "weather": w["weather"],
                      "elevationAscended_m": w["elevation_m"],
                      "avgPace": w["avgPace"]},
        )
        add(**workout)
        steps_n = max(1, w["durMin"] // 5)
        for i in range(steps_n):
            t = w_start + timedelta(minutes=i * 5)
            hr = w["avgHR"] + random.randint(-6, (w["maxHR"] - w["avgHR"]))
            quantity("heartRate", min(w["maxHR"], hr), "count/min", t,
                     context="workout")


records.sort(key=lambda r: r["start"])

with open("sedentary_user_week.jsonl", "w", encoding="utf-8") as f:
    for r in records:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")

print(f"wrote {len(records)} records -> sedentary_user_week.jsonl")
