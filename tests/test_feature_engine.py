"""Tests for typeguard.feature_engine extraction logic."""
import pytest


# ---------------------------------------------------------------------------
# Helpers to build synthetic keystroke events
# ---------------------------------------------------------------------------

def _make_events(text: str, dwell_ms: float = 100.0, flight_ms: float = 80.0):
    """Build a simple down/up event stream for text with uniform timing."""
    from typeguard.types import KeyEvent
    events = []
    t = 0.0
    for ch in text:
        events.append(KeyEvent(key=ch, event_type="down", timestamp_ms=t))
        events.append(KeyEvent(key=ch, event_type="up", timestamp_ms=t + dwell_ms))
        t += dwell_ms + flight_ms
    return events


def _make_paste_events(text: str):
    """Simulate pasted text: zero dwell, zero flight (all events at same time)."""
    from typeguard.types import KeyEvent
    events = []
    t = 0.0
    for ch in text:
        events.append(KeyEvent(key=ch, event_type="down", timestamp_ms=t))
        events.append(KeyEvent(key=ch, event_type="up", timestamp_ms=t))
    return events


def _make_rollover_events():
    """Build events where 'h' and 'e' overlap (rollover):
    h_down -> e_down -> h_up -> e_up
    """
    from typeguard.types import KeyEvent
    return [
        KeyEvent(key="h", event_type="down", timestamp_ms=0.0),
        KeyEvent(key="e", event_type="down", timestamp_ms=25.0),  # before h_up
        KeyEvent(key="h", event_type="up", timestamp_ms=40.0),
        KeyEvent(key="e", event_type="up", timestamp_ms=140.0),
    ]


# ---------------------------------------------------------------------------
# Timing channel tests
# ---------------------------------------------------------------------------

class TestTimingChannels:

    def test_hold_latency(self):
        """HL = keydown -> keyup for same key."""
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("ab", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        channels = engine.extract_timing_channels(events)
        assert len(channels.hl) == 2
        assert all(abs(h - 100.0) < 0.01 for h in channels.hl)

    def test_inter_key_latency(self):
        """IL = keyup[n] -> keydown[n+1]."""
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("ab", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        channels = engine.extract_timing_channels(events)
        assert len(channels.il) == 1
        assert abs(channels.il[0] - 80.0) < 0.01

    def test_down_down_latency(self):
        """DD = keydown[n] -> keydown[n+1]."""
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("ab", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        channels = engine.extract_timing_channels(events)
        assert len(channels.dd) == 1
        assert abs(channels.dd[0] - 180.0) < 0.01  # dwell + flight

    def test_up_up_latency(self):
        """UU = keyup[n] -> keyup[n+1]."""
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("ab", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        channels = engine.extract_timing_channels(events)
        assert len(channels.uu) == 1
        assert abs(channels.uu[0] - 180.0) < 0.01  # same as DD with uniform timing

    def test_up_down_latency(self):
        """UD = keyup[n] -> keydown[n+1] (same as IL for non-overlapping)."""
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("ab", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        channels = engine.extract_timing_channels(events)
        assert len(channels.ud) == 1
        assert abs(channels.ud[0] - 80.0) < 0.01

    def test_rollover_negative_ud(self):
        """When rollover occurs, UD should be negative (next key down before prev up)."""
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_rollover_events()
        engine = TypeGuardFeatureEngine()
        channels = engine.extract_timing_channels(events)
        # e_down (25) - h_up (40) = -15 => UD is negative
        assert len(channels.ud) == 1
        assert channels.ud[0] < 0

    def test_three_char_sequence(self):
        """Three characters should produce 2 IL, 2 DD, 2 UU, 2 UD, 3 HL."""
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("abc", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        channels = engine.extract_timing_channels(events)
        assert len(channels.hl) == 3
        assert len(channels.il) == 2
        assert len(channels.dd) == 2
        assert len(channels.uu) == 2
        assert len(channels.ud) == 2

    def test_empty_events(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        engine = TypeGuardFeatureEngine()
        channels = engine.extract_timing_channels([])
        assert len(channels.hl) == 0
        assert len(channels.il) == 0

    def test_single_key(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("a", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        channels = engine.extract_timing_channels(events)
        assert len(channels.hl) == 1
        assert len(channels.il) == 0


# ---------------------------------------------------------------------------
# Full feature extraction tests
# ---------------------------------------------------------------------------

class TestFeatureExtraction:

    def test_extract_returns_feature_vector(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        from typeguard.types import FeatureVector
        events = _make_events("hello world", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert isinstance(fv, FeatureVector)

    def test_extract_timing_stats(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("hello", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert abs(fv.hl_mean - 100.0) < 1.0
        assert abs(fv.il_mean - 80.0) < 1.0

    def test_extract_cross_hand_ratio(self):
        """'he' is cross-hand (h=right, e=left). Ratio should be > 0."""
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("he", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.cross_hand_ratio > 0

    def test_extract_same_finger_ratio(self):
        """'ed' uses left middle finger for both. Ratio should be > 0."""
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("ed", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.same_finger_ratio > 0

    def test_rollover_ratio_zero_for_non_overlapping(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("hello", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.rollover_ratio == 0.0

    def test_rollover_ratio_positive_for_overlapping(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_rollover_events()
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.rollover_ratio > 0

    def test_digraph_timings_populated(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("the", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert "th" in fv.digraph_timings or "he" in fv.digraph_timings

    def test_total_events_count(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("abc", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.total_events == 6  # 3 down + 3 up

    def test_total_duration(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("ab", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        # a_down=0, a_up=100, b_down=180, b_up=280
        assert abs(fv.total_duration_ms - 280.0) < 1.0


# ---------------------------------------------------------------------------
# Provenance feature tests (paste detection)
# ---------------------------------------------------------------------------

class TestProvenanceFeatures:

    def test_zero_dwell_ratio_for_paste(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_paste_events("hello")
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.zero_dwell_ratio == 1.0

    def test_zero_dwell_ratio_for_human(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("hello", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.zero_dwell_ratio == 0.0

    def test_zero_flight_ratio_for_paste(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_paste_events("hello")
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.zero_flight_ratio == 1.0

    def test_zero_flight_ratio_for_human(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("hello", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.zero_flight_ratio == 0.0

    def test_synthetic_burst_detection(self):
        """8+ consecutive keys with dwell AND flight < 5ms = synthetic burst."""
        from typeguard.types import KeyEvent
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = []
        t = 0.0
        for ch in "abcdefghij":  # 10 chars
            events.append(KeyEvent(key=ch, event_type="down", timestamp_ms=t))
            events.append(KeyEvent(key=ch, event_type="up", timestamp_ms=t + 2.0))  # 2ms dwell
            t += 4.0  # 2ms flight
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.synthetic_burst_count >= 1


# ---------------------------------------------------------------------------
# Pause ecology and burst structure tests
# ---------------------------------------------------------------------------

class TestPauseEcology:

    def test_pause_detection(self):
        """A gap > 500ms in flight should count as a pause."""
        from typeguard.types import KeyEvent
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = [
            KeyEvent(key="a", event_type="down", timestamp_ms=0.0),
            KeyEvent(key="a", event_type="up", timestamp_ms=100.0),
            # 600ms gap
            KeyEvent(key="b", event_type="down", timestamp_ms=700.0),
            KeyEvent(key="b", event_type="up", timestamp_ms=800.0),
        ]
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.pause_count >= 1

    def test_burst_length(self):
        """Consecutive fast keystrokes form a burst."""
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("hello world", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.avg_burst_length > 0

    def test_long_pause_ratio(self):
        """Long pauses (>1000ms) as fraction of total pauses."""
        from typeguard.types import KeyEvent
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = [
            KeyEvent(key="a", event_type="down", timestamp_ms=0.0),
            KeyEvent(key="a", event_type="up", timestamp_ms=100.0),
            # 1500ms gap (long pause)
            KeyEvent(key="b", event_type="down", timestamp_ms=1600.0),
            KeyEvent(key="b", event_type="up", timestamp_ms=1700.0),
            # 100ms gap (normal)
            KeyEvent(key="c", event_type="down", timestamp_ms=1800.0),
            KeyEvent(key="c", event_type="up", timestamp_ms=1900.0),
        ]
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.long_pause_ratio > 0


# ---------------------------------------------------------------------------
# Distribution shape tests
# ---------------------------------------------------------------------------

class TestDistributionShape:

    def test_iki_skewness_computed(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("abcdefghij", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        # With uniform timing, skewness should be ~0
        assert isinstance(fv.iki_skewness, float)

    def test_iki_kurtosis_computed(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("abcdefghij", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert isinstance(fv.iki_kurtosis, float)


# ---------------------------------------------------------------------------
# Fatigue curve
# ---------------------------------------------------------------------------

class TestFatigueCurve:

    def test_fatigue_slope_computed(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = _make_events("hello world this is a test", dwell_ms=100.0, flight_ms=80.0)
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert isinstance(fv.fatigue_slope, float)


# ---------------------------------------------------------------------------
# Backspace handling
# ---------------------------------------------------------------------------

class TestBackspaceHandling:

    def test_backspace_rate(self):
        from typeguard.types import KeyEvent
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = [
            KeyEvent(key="h", event_type="down", timestamp_ms=0.0),
            KeyEvent(key="h", event_type="up", timestamp_ms=100.0),
            KeyEvent(key="Backspace", event_type="down", timestamp_ms=200.0),
            KeyEvent(key="Backspace", event_type="up", timestamp_ms=250.0),
            KeyEvent(key="e", event_type="down", timestamp_ms=350.0),
            KeyEvent(key="e", event_type="up", timestamp_ms=450.0),
        ]
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        # 1 backspace out of 3 down events = 0.333
        assert abs(fv.backspace_rate - 1.0 / 3.0) < 0.01


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

class TestEdgeCases:

    def test_extract_with_single_event(self):
        from typeguard.types import KeyEvent
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = [KeyEvent(key="a", event_type="down", timestamp_ms=0.0)]
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.total_events == 1

    def test_extract_with_no_events(self):
        from typeguard.feature_engine import TypeGuardFeatureEngine
        engine = TypeGuardFeatureEngine()
        fv = engine.extract([])
        assert fv.total_events == 0
        assert fv.hl_mean == 0.0

    def test_extract_with_only_downs(self):
        from typeguard.types import KeyEvent
        from typeguard.feature_engine import TypeGuardFeatureEngine
        events = [
            KeyEvent(key="a", event_type="down", timestamp_ms=0.0),
            KeyEvent(key="b", event_type="down", timestamp_ms=100.0),
        ]
        engine = TypeGuardFeatureEngine()
        fv = engine.extract(events)
        assert fv.total_events == 2
        # Digraph DD timing still computed from consecutive downs
        assert "ab" in fv.digraph_timings
        assert abs(fv.digraph_timings["ab"] - 100.0) < 0.01
