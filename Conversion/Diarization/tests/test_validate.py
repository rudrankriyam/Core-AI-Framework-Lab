from validate import select_ami_windows


def test_ami_windows_measure_spacing_from_the_previous_window_end() -> None:
    windows = select_ami_windows(
        {"A": [(0.0, 20.0), (9.0, 30.0)]},
        duration=10.0,
    )

    assert len(windows) == 2
    assert windows[1][1] - windows[0][2] >= 8.0


def test_ami_windows_can_share_one_long_segment() -> None:
    windows = select_ami_windows(
        {"A": [(0.0, 30.0)]},
        duration=10.0,
    )

    assert len(windows) == 2
    assert windows[1][1] - windows[0][2] >= 8.0
    assert windows[1][2] <= 29.8
