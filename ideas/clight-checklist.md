# clight post-reboot checklist

1. **Dark room floor** — backlight stays at ≥10% instead of going to 0
2. **DPMS recovery** — if the display does go off after 10 min idle, mouse/keypress
   should wake it normally (no `swaymsg` incantation needed, since this time clight
   will have started cleanly)
3. **Dimmer** — 60s on battery before it dims, and dims to 40% rather than invisibly low

## Tuning

If the dark-room floor still feels too low, raise the first value in `ac_regression_points`:

```
/etc/clight/modules.conf.d/sensor.conf
```

Bump `0.10` toward `0.15` or `0.20` as needed, then `etckeeper commit`.
