# Pibo environment audio sources

Downloaded on 2026-07-13 from Mixkit's official sound-effect downloads.
The WAV files are source masters; selected files are packaged in the app as
derived AAC-LC assets under `Pibo/Resources/Audio/Ambience/`.

License page: https://mixkit.co/license/#sfxFree

| Local file | Mixkit title | ID | Duration | Source page |
| --- | --- | ---: | ---: | --- |
| `rain_light_loop_mixkit_2393.wav` | Light rain loop | 2393 | 15.00 s | https://mixkit.co/free-sound-effects/rain/ |
| `rain_heavy_storm_loop_mixkit_2400.wav` | Heavy storm rain loop | 2400 | 18.00 s | https://mixkit.co/free-sound-effects/thunder/ |
| `thunderstorm_rain_loop_mixkit_2402.wav` | Thunderstorm and rain loop | 2402 | 52.75 s | https://mixkit.co/free-sound-effects/thunder/ |
| `thunderstorm_rain_mixkit_2390.wav` | Rain and thunder storm | 2390 | 29.00 s | https://mixkit.co/free-sound-effects/rain/ |
| `thunder_deep_rumble_mixkit_1296.wav` | Thunder deep rumble | 1296 | 18.17 s | https://mixkit.co/free-sound-effects/thunder/ |
| `thunder_big_rumble_mixkit_1297.wav` | Big thunder rumble | 1297 | 22.74 s | https://mixkit.co/free-sound-effects/thunder/ |
| `thunder_distant_mixkit_1292.wav` | Distant thunder storm explosion | 1292 | 9.31 s | https://mixkit.co/free-sound-effects/thunder/ |
| `forest_day_ambience_mixkit_1213.wav` | European forest ambience | 1213 | 161.30 s | https://mixkit.co/free-sound-effects/forest/ |
| `forest_night_insects_mixkit_2414.wav` | Night forest with insects | 2414 | 84.00 s | https://mixkit.co/free-sound-effects/forest/ |
| `forest_wind_mixkit_1237.wav` | Wind in the forest | 1237 | 25.32 s | https://mixkit.co/free-sound-effects/forest/ |
| `rainforest_birds_mixkit_2434.wav` | Birds in the jungle | 2434 | 60.83 s | https://mixkit.co/free-sound-effects/jungle/ |
| `rainforest_river_mixkit_2451.wav` | River surroundings in the jungle | 2451 | 60.14 s | https://mixkit.co/free-sound-effects/jungle/ |
| `rainforest_twilight_mixkit_2420.wav` | Twilight jungle | 2420 | 13.57 s | https://mixkit.co/free-sound-effects/jungle/ |

All downloaded assets are stereo, 44.1 kHz PCM WAV files. The rainforest bird
and river recordings are 24-bit; the remaining files are 16-bit.

## Packaged derivatives

Looping ambience was rendered with a 1.5-second circular equal-power crossfade
before encoding. Thunder assets remain one-shots. All derivatives are stereo,
44.1 kHz, AAC-LC at 128 kbps. The two mixed thunderstorm recordings are not
packaged because rain and thunder are mixed independently at runtime.

| App asset | Source master |
| --- | --- |
| `ambient_forest_day.m4a` | `forest_day_ambience_mixkit_1213.wav` |
| `ambient_forest_night.m4a` | `forest_night_insects_mixkit_2414.wav` |
| `ambient_forest_wind.m4a` | `forest_wind_mixkit_1237.wav` |
| `ambient_rainforest_river.m4a` | `rainforest_river_mixkit_2451.wav` |
| `ambient_rainforest_birds.m4a` | `rainforest_birds_mixkit_2434.wav` |
| `ambient_rainforest_twilight.m4a` | `rainforest_twilight_mixkit_2420.wav` |
| `weather_rain_light.m4a` | `rain_light_loop_mixkit_2393.wav` |
| `weather_rain_heavy.m4a` | `rain_heavy_storm_loop_mixkit_2400.wav` |
| `weather_thunder_distant.m4a` | `thunder_distant_mixkit_1292.wav` |
| `weather_thunder_deep.m4a` | `thunder_deep_rumble_mixkit_1296.wav` |
| `weather_thunder_big.m4a` | `thunder_big_rumble_mixkit_1297.wav` |

## SHA-256

```text
c905c9532f821805d089bec63cb112f770ab5603f54c95721366a649375340e0  rain_heavy_storm_loop_mixkit_2400.wav
0e90fa5f678cca6966e66477b75b8fe608bf845d54e4b3e3efff839b9cc6805e  rain_light_loop_mixkit_2393.wav
9a2f96945fff214732bd416d97ed0269e822bc0a811108e32e12c422e6dda67f  thunder_big_rumble_mixkit_1297.wav
b5edb9649bc153cf517757ed53a2f3fd51264a6cb73d6895c140586612ec00fc  thunder_deep_rumble_mixkit_1296.wav
24578b0fcb31cfaa64b73c4622ed287cf17f7a1563a2bf45da46382d73680877  thunder_distant_mixkit_1292.wav
4e24e73f469cca61f518b509fdcee1d24897ffb19a8f3a3a2f783f1073af678b  thunderstorm_rain_loop_mixkit_2402.wav
69ca82bbd8b98b94caabf8ffe04e95c4821965a7c1fbb3f028778091520bfb03  thunderstorm_rain_mixkit_2390.wav
b3b445e9813196d328096ce41db8e382fdcbec95780fc632f8b66132482d4ac3  forest_day_ambience_mixkit_1213.wav
4a1e9c5cada898737a47c081117365907368fdc25acb8f66b8402d757320d4d0  forest_night_insects_mixkit_2414.wav
b752cf82a27e4664b665bb876e252077c2202318541f1c9c4b166cb3b19478f2  forest_wind_mixkit_1237.wav
7fba8dec1f1cf61b7c2b9871e7c4dee32a760725a87354dd357002a1bf2c3f53  rainforest_birds_mixkit_2434.wav
681078dcf9f0d943bf58e77d018c3e8eca0bebeaec98230511bfed97dbaf0478  rainforest_river_mixkit_2451.wav
d79423f978ef27b8d47cfc0bad8087cfa113fd2734edf897ca4185c9ca8984ac  rainforest_twilight_mixkit_2420.wav
```

### Packaged derivative SHA-256

```text
b29abf1c3a3860e3433faf4e30fe62205f353fa9ff9a412ff324dd18e07a58ed  ambient_forest_day.m4a
a199bf722459d6167403e13a0028f1536e7f9fa28bc793691c30699407e95309  ambient_forest_night.m4a
8ad17e088a6b2dcdac055fe7a24768c15a5215cdf822c5292f50fced8d8fd11e  ambient_forest_wind.m4a
4e67af16678f2849cb3203f39c62dcafccd271870c9a0c9c5eaba784edc59dbb  ambient_rainforest_birds.m4a
b8392f7caf367877ba24f0875341e4c95046b380b01666e0dc2642be85d05220  ambient_rainforest_river.m4a
3d6fa073eb883dbf1124d8b4a8b5c5cf15793eabf69d61b3a80e495ed536ab4d  ambient_rainforest_twilight.m4a
e81d0f71a93ebfc45e72f60a7edda0f53edac5543997acb4b61b5e7a91ca6e5a  weather_rain_heavy.m4a
e0234eba3c7b8a81bb2fd41513f78ab6066a7993b5e11e234eaacd86e4a42efd  weather_rain_light.m4a
061bf0baf940fce86d9363227f2c349068f7c08bd93f036c143eabeb701072ec  weather_thunder_big.m4a
10684355a50227e42c4217faf136a80a0291a5442cb6769196c07675474b6ba7  weather_thunder_deep.m4a
dc7d300ffab17d86705472d7ecf8b30f17ffd1db41cdeadf8e5dcd7d452b863b  weather_thunder_distant.m4a
```
