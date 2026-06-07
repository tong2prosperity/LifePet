#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pibo mock 数据生成器 —— 爱运动用户一周 HealthKit 数据。

口径：模拟「Apple Watch 采集 → 写入 HealthKit → iOS 可读」这条链路（见
docs/health-data/apple-watch-healthkit-data-catalog.md）。所有记录尽量贴近
真实 HealthKit 的样本形状：quantity / category / workout / series 四类。

人物画像：
  阿凯，28 岁，规律健身爱好者，戴表入睡。
  静息心率 ~50bpm，VO2max ~48，HRV 基线 ~65ms。
  一周训练安排（2026-06-01 周一 ~ 06-07 周日）：
    Mon 晨跑 8km（变速）   Tue 力量训练   Wed 长距离骑行 35km
    Thu 恢复日 瑜伽+冥想   Fri HIIT 25min  Sat 越野徒步 15km
    Sun 游泳 1500m + 散步

输出：active_user_week.jsonl（按时间排序，一行一条记录）
运行：python3 generate.py
"""

import json
import random
from datetime import datetime, timedelta, timezone

random.seed(20260601)  # 固定种子，可复现

TZ = timezone(timedelta(hours=8))  # Asia/Shanghai
WATCH = "Apple Watch Series 9"     # 数据来源（只模拟手表写入的数据）

records = []


def iso(dt: datetime) -> str:
    return dt.isoformat(timespec="seconds")


def add(**kw):
    records.append(kw)


def quantity(qtype, value, unit, start, end=None, tier="A", **extra):
    """累计/瞬时 数量型样本。"""
    rec = dict(
        type=qtype, sampleClass="quantity", value=value, unit=unit,
        start=iso(start), end=iso(end or start), source=WATCH, tier=tier,
    )
    rec.update(extra)
    add(**rec)


def category(ctype, value, start, end, tier="A", **extra):
    rec = dict(
        type=ctype, sampleClass="category", value=value,
        start=iso(start), end=iso(end), source=WATCH, tier=tier,
    )
    rec.update(extra)
    add(**rec)


def day_at(base: datetime, h, m=0):
    return base.replace(hour=h, minute=m, second=0, microsecond=0)


# ---------------------------------------------------------------------------
# 每日训练计划
# ---------------------------------------------------------------------------
PLAN = [
    # weekday label, workout dict or None, day-level intensity knobs
    {
        "label": "周一·晨跑", "date": "2026-06-01",
        "workout": {
            "activityType": "running", "startH": 6, "startM": 30, "durMin": 46,
            "distance_m": 8000, "kcal": 545, "avgHR": 156, "maxHR": 181,
            "indoor": False, "weather": "晴 21℃", "elevation_m": 78,
            "avgPace": "5:45/km", "laps_km": 8, "recoveryHR": 32,
            "dynamics": True,
        },
        "steps": 16800, "active_kcal": 720, "exercise_min": 58,
        "stand_h": 12, "flights": 9, "rhr": 49, "whr_avg": 102,
        "hrv": 71, "vo2": 48.2, "mindful": None,
        "sleep_start": ("2026-05-31", 23, 10), "sleep_dur_h": 7.4,
        "resp_rate": 13.6, "wrist_temp_dev": -0.1,
    },
    {
        "label": "周二·力量", "date": "2026-06-02",
        "workout": {
            "activityType": "functionalStrengthTraining", "startH": 19, "startM": 15,
            "durMin": 52, "distance_m": 0, "kcal": 410, "avgHR": 128, "maxHR": 162,
            "indoor": True, "weather": None, "elevation_m": 0,
            "avgPace": None, "laps_km": 0, "recoveryHR": 28, "dynamics": False,
        },
        "steps": 9600, "active_kcal": 560, "exercise_min": 54,
        "stand_h": 11, "flights": 6, "rhr": 51, "whr_avg": 98,
        "hrv": 63, "vo2": None, "mindful": None,
        "sleep_start": ("2026-06-01", 23, 35), "sleep_dur_h": 7.1,
        "resp_rate": 14.1, "wrist_temp_dev": 0.2,
    },
    {
        "label": "周三·骑行", "date": "2026-06-03",
        "workout": {
            "activityType": "cycling", "startH": 17, "startM": 40, "durMin": 78,
            "distance_m": 35200, "kcal": 690, "avgHR": 141, "maxHR": 169,
            "indoor": False, "weather": "多云 24℃", "elevation_m": 246,
            "avgPace": None, "laps_km": 0, "recoveryHR": 35, "dynamics": False,
        },
        "steps": 8200, "active_kcal": 810, "exercise_min": 82,
        "stand_h": 10, "flights": 4, "rhr": 50, "whr_avg": 96,
        "hrv": 66, "vo2": None, "mindful": None,
        "sleep_start": ("2026-06-02", 23, 50), "sleep_dur_h": 6.8,
        "resp_rate": 14.4, "wrist_temp_dev": 0.3,
    },
    {
        "label": "周四·恢复", "date": "2026-06-04",
        "workout": {
            "activityType": "yoga", "startH": 7, "startM": 0, "durMin": 35,
            "distance_m": 0, "kcal": 120, "avgHR": 92, "maxHR": 112,
            "indoor": True, "weather": None, "elevation_m": 0,
            "avgPace": None, "laps_km": 0, "recoveryHR": None, "dynamics": False,
        },
        "steps": 11200, "active_kcal": 380, "exercise_min": 41,
        "stand_h": 13, "flights": 7, "rhr": 48, "whr_avg": 94,
        "hrv": 78, "vo2": None, "mindful": [(7, 40, 10), (22, 30, 8)],
        "sleep_start": ("2026-06-03", 23, 5), "sleep_dur_h": 8.1,
        "resp_rate": 13.2, "wrist_temp_dev": -0.2,
    },
    {
        "label": "周五·HIIT", "date": "2026-06-05",
        "workout": {
            "activityType": "highIntensityIntervalTraining", "startH": 12, "startM": 30,
            "durMin": 25, "distance_m": 0, "kcal": 320, "avgHR": 158, "maxHR": 186,
            "indoor": True, "weather": None, "elevation_m": 0,
            "avgPace": None, "laps_km": 0, "recoveryHR": 41, "dynamics": False,
        },
        "steps": 12400, "active_kcal": 610, "exercise_min": 38,
        "stand_h": 12, "flights": 8, "rhr": 50, "whr_avg": 101,
        "hrv": 60, "vo2": 48.6, "mindful": None,
        "sleep_start": ("2026-06-04", 0, 15), "sleep_dur_h": 6.5,
        "resp_rate": 14.6, "wrist_temp_dev": 0.4,
    },
    {
        "label": "周六·徒步", "date": "2026-06-06",
        "workout": {
            "activityType": "hiking", "startH": 8, "startM": 20, "durMin": 215,
            "distance_m": 15400, "kcal": 1180, "avgHR": 124, "maxHR": 158,
            "indoor": False, "weather": "晴 19℃ 山区", "elevation_m": 720,
            "avgPace": "13:58/km", "laps_km": 0, "recoveryHR": 30, "dynamics": False,
        },
        "steps": 24600, "active_kcal": 1280, "exercise_min": 168,
        "stand_h": 13, "flights": 41, "rhr": 49, "whr_avg": 99,
        "hrv": 69, "vo2": None, "mindful": None,
        "sleep_start": ("2026-06-05", 23, 0), "sleep_dur_h": 8.4,
        "resp_rate": 13.0, "wrist_temp_dev": -0.1,
    },
    {
        "label": "周日·游泳", "date": "2026-06-07",
        "workout": {
            "activityType": "swimming", "startH": 10, "startM": 0, "durMin": 42,
            "distance_m": 1500, "kcal": 430, "avgHR": 134, "maxHR": 161,
            "indoor": True, "weather": None, "elevation_m": 0,
            "avgPace": "2:48/100m", "laps_km": 0, "recoveryHR": 33,
            "dynamics": False, "strokes": 612,
        },
        "steps": 7800, "active_kcal": 520, "exercise_min": 47,
        "stand_h": 11, "flights": 3, "rhr": 50, "whr_avg": 95,
        "hrv": 72, "vo2": None, "mindful": [(21, 0, 12)],
        "sleep_start": ("2026-06-06", 22, 50), "sleep_dur_h": 8.0,
        "resp_rate": 13.4, "wrist_temp_dev": -0.2,
    },
]


def parse_date(s):
    y, m, d = map(int, s.split("-"))
    return datetime(y, m, d, tzinfo=TZ)


# ---------------------------------------------------------------------------
# 逐日生成
# ---------------------------------------------------------------------------
for day in PLAN:
    base = parse_date(day["date"])
    midnight = day_at(base, 0, 0)
    end_of_day = day_at(base, 23, 59)

    # --- 睡眠（归属当天，记录前一晚入睡到当天清晨） ---------------------
    sy, sh, sm = day["sleep_start"]
    sd = datetime(*map(int, sy.split("-")), sh, sm, tzinfo=TZ)
    total_sleep = timedelta(hours=day["sleep_dur_h"])
    sleep_end = sd + total_sleep + timedelta(minutes=random.randint(15, 35))  # 含少量清醒
    # 阶段切分：core 55% / deep 18% / rem 22% / awake 5%
    cur = sd
    stages = [
        ("asleepCore", 0.30), ("asleepDeep", 0.10), ("asleepREM", 0.08),
        ("asleepCore", 0.18), ("asleepDeep", 0.08), ("awake", 0.03),
        ("asleepREM", 0.14), ("asleepCore", 0.09),
    ]
    category("sleepAnalysis", "inBed", sd, sleep_end, tier="B", note="整段卧床")
    for stage, frac in stages:
        dur = total_sleep * frac
        nxt = cur + dur
        category("sleepAnalysis", stage, cur, nxt, tier="B")
        cur = nxt
    # 睡眠相关：呼吸频率、手腕温度、血氧（夜间各一条）
    mid_sleep = sd + total_sleep / 2
    quantity("respiratoryRate", day["resp_rate"], "count/min", mid_sleep, tier="C",
             context="sleep")
    quantity("appleSleepingWristTemperature", round(day["wrist_temp_dev"], 1),
             "degC", mid_sleep, tier="C", note="相对个人基线偏差")
    quantity("oxygenSaturation", random.randint(96, 99), "%", mid_sleep, tier="C",
             context="sleep")

    # --- 当日累计型（一条日总量，start=00:00 end=23:59） ----------------
    # 步行+跑步距离按步数派生即可——跑步/徒步的步数本就计入 stepCount，
    # 不再叠加 workout 距离，避免重复计数。
    dist_km = round(day["steps"] * 0.00072, 2)
    quantity("stepCount", day["steps"], "count", midnight, end_of_day)
    quantity("distanceWalkingRunning", dist_km, "km", midnight, end_of_day)
    quantity("activeEnergyBurned", day["active_kcal"], "kcal", midnight, end_of_day)
    quantity("basalEnergyBurned", random.randint(1560, 1660), "kcal",
             midnight, end_of_day)
    quantity("appleExerciseTime", day["exercise_min"], "min", midnight, end_of_day)
    quantity("appleStandTime", day["stand_h"] * 60 - random.randint(0, 40), "min",
             midnight, end_of_day)
    quantity("flightsClimbed", day["flights"], "count", midnight, end_of_day)
    quantity("appleMoveTime", day["exercise_min"] + random.randint(20, 60), "min",
             midnight, end_of_day)

    # 站立小时事件（白天每小时若干 idle/stood）
    stood_hours = sorted(random.sample(range(7, 23), day["stand_h"]))
    for h in stood_hours:
        category("appleStandHour", "stood", day_at(base, h, 0),
                 day_at(base, h, 1))

    # --- 心率类瞬时样本 -------------------------------------------------
    quantity("restingHeartRate", day["rhr"], "count/min", day_at(base, 6, 0),
             tier="A")
    quantity("walkingHeartRateAverage", day["whr_avg"], "count/min",
             day_at(base, 18, 0), tier="A")
    quantity("heartRateVariabilitySDNN", day["hrv"], "ms", day_at(base, 6, 5),
             tier="A", context="morning")
    if day["vo2"]:
        quantity("vo2Max", day["vo2"], "mL/min·kg", day_at(base, 12, 0), tier="B")

    # 全天散点心率（晨低 / 日常 / 训练高峰 / 傻晚回落）
    w = day["workout"]
    hr_schedule = [
        (3, 0, day["rhr"] - 4), (6, 10, day["rhr"]), (8, 30, 78),
        (11, 0, 88), (14, 30, 84), (16, 0, 92), (20, 30, 80),
        (22, 30, day["rhr"] + 6),
    ]
    for h, m, v in hr_schedule:
        quantity("heartRate", v + random.randint(-3, 3), "count/min",
                 day_at(base, h, m), tier="A")
    # 训练时段高频心率（每 5 分钟一条）
    w_start = day_at(base, w["startH"], w["startM"])
    steps_n = max(1, w["durMin"] // 5)
    for i in range(steps_n):
        t = w_start + timedelta(minutes=i * 5)
        frac = i / max(1, steps_n - 1)
        # 钟形曲线：开头/结尾接近 avg，训练中段冲到 max 附近
        bell = 1 - abs(frac - 0.5) * 2          # 0→1→0
        hr = int(w["avgHR"] + (w["maxHR"] - w["avgHR"]) * bell * 0.85)
        hr = max(w["avgHR"] - 12, min(w["maxHR"], hr + random.randint(-5, 6)))
        quantity("heartRate", hr, "count/min", t, tier="A", context="workout")

    # --- 正念/冥想 ------------------------------------------------------
    for (mh, mm, mdur) in (day["mindful"] or []):
        ms = day_at(base, mh, mm)
        category("mindfulSession", "session", ms, ms + timedelta(minutes=mdur),
                 tier="B")
        # 冥想时再补一条 HRV（通常升高）
        quantity("heartRateVariabilitySDNN", day["hrv"] + random.randint(6, 16),
                 "ms", ms + timedelta(minutes=mdur // 2), tier="A",
                 context="mindful")

    # --- 环境 / 日照 ----------------------------------------------------
    quantity("environmentalAudioExposure", random.randint(58, 74), "dBASPL",
             day_at(base, 15, 0), tier="A")
    quantity("timeInDaylight", random.randint(45, 180), "min",
             midnight, end_of_day, tier="A")
    if w["activityType"] in ("running", "cycling", "hiking"):
        quantity("timeInDaylight", w["durMin"], "min", w_start,
                 w_start + timedelta(minutes=w["durMin"]), tier="A",
                 context="outdoor-workout")

    # --- Workout 主记录 -------------------------------------------------
    w_end = w_start + timedelta(minutes=w["durMin"])
    workout = dict(
        type="workout", sampleClass="workout",
        activityType=w["activityType"],
        start=iso(w_start), end=iso(w_end), durationSec=w["durMin"] * 60,
        totalDistance_m=w["distance_m"], totalEnergyBurned_kcal=w["kcal"],
        avgHeartRate_bpm=w["avgHR"], maxHeartRate_bpm=w["maxHR"],
        source=WATCH, tier="B",
        metadata={
            "indoor": w["indoor"],
            "weather": w["weather"],
            "elevationAscended_m": w["elevation_m"],
            "avgPace": w["avgPace"],
        },
    )
    if "strokes" in w:
        workout["metadata"]["swimmingStrokeCount"] = w["strokes"]
    if w["recoveryHR"]:
        workout["metadata"]["heartRateRecoveryOneMinute_bpm"] = w["recoveryHR"]

    # 跑步分段（每公里 lap）+ 跑步动态
    if w["laps_km"] and w["laps_km"] > 0:
        laps = []
        pace_base = 345  # 秒/公里 ~5:45
        cur_t = w_start
        for k in range(w["laps_km"]):
            # 变速跑：偶数公里更快
            pace = pace_base + random.randint(-18, 22) - (12 if k % 2 else 0)
            lap_end = cur_t + timedelta(seconds=pace)
            laps.append({
                "lap": k + 1,
                "start": iso(cur_t), "end": iso(lap_end),
                "distance_m": 1000,
                "pace": f"{pace // 60}:{pace % 60:02d}/km",
                "avgHR_bpm": w["avgHR"] + random.randint(-8, 10),
            })
            cur_t = lap_end
        workout["laps"] = laps
    add(**workout)

    # 跑步动态序列（仅跑步日，每 2 分钟一条代表样本）
    if w.get("dynamics"):
        for i in range(0, w["durMin"], 2):
            t = w_start + timedelta(minutes=i)
            quantity("runningSpeed", round(random.uniform(2.7, 3.4), 2), "m/s",
                     t, tier="B", context="workout")
            quantity("runningPower", random.randint(255, 310), "W", t, tier="B",
                     context="workout")
            quantity("runningStrideLength", round(random.uniform(1.05, 1.25), 2),
                     "m", t, tier="B", context="workout")
            quantity("runningVerticalOscillation",
                     round(random.uniform(7.2, 9.1), 1), "cm", t, tier="B",
                     context="workout")
            quantity("runningGroundContactTime", random.randint(228, 258), "ms",
                     t, tier="B", context="workout")

    # 专项距离（骑行/游泳额外补距离样本）
    if w["activityType"] == "cycling":
        quantity("distanceCycling", round(w["distance_m"] / 1000, 1), "km",
                 w_start, w_end, tier="B", context="workout")
    if w["activityType"] == "swimming":
        quantity("distanceSwimming", w["distance_m"], "m", w_start, w_end,
                 tier="B", context="workout")
        quantity("swimmingStrokeCount", w["strokes"], "count", w_start, w_end,
                 tier="B", context="workout")

    # 运动后心率恢复
    if w["recoveryHR"]:
        quantity("heartRateRecoveryOneMinute", w["recoveryHR"], "count/min",
                 w_end + timedelta(minutes=1), tier="B")


# ---------------------------------------------------------------------------
# 排序输出
# ---------------------------------------------------------------------------
records.sort(key=lambda r: r["start"])

with open("active_user_week.jsonl", "w", encoding="utf-8") as f:
    for r in records:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")

print(f"wrote {len(records)} records -> active_user_week.jsonl")
