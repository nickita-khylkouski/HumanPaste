"""Tests for typeguard.keyboard_layout QWERTY mapping."""
import pytest


def test_all_alpha_keys_mapped():
    from typeguard.keyboard_layout import get_key_info
    for c in "abcdefghijklmnopqrstuvwxyz":
        info = get_key_info(c)
        assert info is not None, f"Key '{c}' not mapped"
        assert info.hand in ("left", "right")
        assert info.finger in ("pinky", "ring", "middle", "index", "thumb")
        assert isinstance(info.row, int)


def test_number_row_mapped():
    from typeguard.keyboard_layout import get_key_info
    for c in "0123456789":
        info = get_key_info(c)
        assert info is not None, f"Number '{c}' not mapped"
        assert info.row == 2


def test_space_mapped():
    from typeguard.keyboard_layout import get_key_info
    info = get_key_info(" ")
    assert info is not None
    assert info.finger == "thumb"
    assert info.hand == "right"


def test_case_insensitive():
    from typeguard.keyboard_layout import get_key_info
    lower = get_key_info("a")
    upper = get_key_info("A")
    assert lower is not None
    assert upper is not None
    assert lower.hand == upper.hand
    assert lower.finger == upper.finger


def test_left_hand_keys():
    from typeguard.keyboard_layout import get_key_info
    left_keys = "qwertasdfgzxcvb"
    for c in left_keys:
        info = get_key_info(c)
        assert info.hand == "left", f"Key '{c}' should be left hand"


def test_right_hand_keys():
    from typeguard.keyboard_layout import get_key_info
    right_keys = "yuiophjklnm"
    for c in right_keys:
        info = get_key_info(c)
        assert info.hand == "right", f"Key '{c}' should be right hand"


def test_home_row():
    from typeguard.keyboard_layout import get_key_info
    home_keys = "asdfghjkl"
    for c in home_keys:
        info = get_key_info(c)
        assert info.row == 0, f"Key '{c}' should be home row (0)"


def test_is_cross_hand():
    from typeguard.keyboard_layout import is_cross_hand
    assert is_cross_hand("f", "j") is True   # left index -> right index
    assert is_cross_hand("t", "h") is True   # left index -> right index
    assert is_cross_hand("a", "s") is False  # both left
    assert is_cross_hand("j", "k") is False  # both right


def test_is_same_finger():
    from typeguard.keyboard_layout import is_same_finger
    assert is_same_finger("e", "d") is True   # both left middle
    assert is_same_finger("r", "t") is True   # both left index
    assert is_same_finger("a", "s") is False  # left pinky vs left ring


def test_unknown_key_returns_none():
    from typeguard.keyboard_layout import get_key_info
    assert get_key_info("\x00") is None
    assert get_key_info("\t") is None


def test_punctuation_keys():
    from typeguard.keyboard_layout import get_key_info
    for c in ";',./":
        info = get_key_info(c)
        assert info is not None, f"Punctuation '{c}' not mapped"
