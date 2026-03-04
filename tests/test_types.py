"""Tests for typeguard.types data classes."""
import pytest


def test_key_event_creation():
    from typeguard.types import KeyEvent
    e = KeyEvent(key="a", event_type="down", timestamp_ms=100.0)
    assert e.key == "a"
    assert e.event_type == "down"
    assert e.timestamp_ms == 100.0


def test_key_event_rejects_invalid_type():
    from typeguard.types import KeyEvent
    with pytest.raises((ValueError, TypeError)):
        KeyEvent(key="a", event_type="press", timestamp_ms=100.0)


def test_timing_channels_creation():
    from typeguard.types import TimingChannels
    tc = TimingChannels(
        hl=[100.0, 110.0],
        il=[50.0, 60.0],
        dd=[150.0, 170.0],
        uu=[160.0, 180.0],
        ud=[50.0, 60.0],
    )
    assert len(tc.hl) == 2
    assert len(tc.il) == 2
    assert len(tc.dd) == 2
    assert len(tc.uu) == 2
    assert len(tc.ud) == 2


def test_feature_vector_creation():
    from typeguard.types import FeatureVector
    fv = FeatureVector(
        hl_mean=100.0,
        hl_std=10.0,
        il_mean=60.0,
        il_std=15.0,
        dd_mean=160.0,
        dd_std=20.0,
        uu_mean=170.0,
        uu_std=22.0,
        ud_mean=60.0,
        ud_std=15.0,
        iki_skewness=1.5,
        iki_kurtosis=5.0,
        hl_skewness=0.5,
        hl_kurtosis=3.0,
        cross_hand_ratio=0.45,
        same_finger_ratio=0.05,
        rollover_ratio=0.25,
        avg_burst_length=5.0,
        burst_pause_ratio=0.7,
        pause_count=3,
        long_pause_ratio=0.1,
        backspace_rate=0.03,
        zero_dwell_ratio=0.0,
        zero_flight_ratio=0.0,
        synthetic_burst_count=0,
        fatigue_slope=0.001,
        digraph_timings={},
        total_events=100,
        total_duration_ms=5000.0,
    )
    assert fv.hl_mean == 100.0
    assert fv.total_events == 100
    assert fv.zero_dwell_ratio == 0.0


def test_feature_vector_to_array():
    from typeguard.types import FeatureVector
    fv = FeatureVector(
        hl_mean=100.0, hl_std=10.0,
        il_mean=60.0, il_std=15.0,
        dd_mean=160.0, dd_std=20.0,
        uu_mean=170.0, uu_std=22.0,
        ud_mean=60.0, ud_std=15.0,
        iki_skewness=1.5, iki_kurtosis=5.0,
        hl_skewness=0.5, hl_kurtosis=3.0,
        cross_hand_ratio=0.45, same_finger_ratio=0.05,
        rollover_ratio=0.25,
        avg_burst_length=5.0, burst_pause_ratio=0.7,
        pause_count=3, long_pause_ratio=0.1,
        backspace_rate=0.03,
        zero_dwell_ratio=0.0, zero_flight_ratio=0.0,
        synthetic_burst_count=0,
        fatigue_slope=0.001,
        digraph_timings={},
        total_events=100, total_duration_ms=5000.0,
    )
    arr = fv.to_array()
    assert isinstance(arr, list)
    assert len(arr) > 20
    assert all(isinstance(x, (int, float)) for x in arr)
