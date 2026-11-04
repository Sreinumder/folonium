# Folonium

Personal KWin/Plasma 6 tiling setup, version controlled in one place.

## Demo
![Demo GIF](tiling_showcase.gif)

Installing:
```bash
./install.sh
```

Uninstalling:
```bash
./install.sh uninstall
```
## What makes this unique
- A rule based approach to tiling rather than a strict pattern like binary tree, dwindle.
  - \[1 2\] respresents a row of windows where each number represents number of windows to be stacked. Similarly, \\1 2\\ represents the same but rotated -90 degrees.
    ```
                [1 2]                         /1 2/
    ┌─────────────┬─────────────┐ ┌───────────────────────────┐
    │             │             │ │                           │
    │             ├─────────────┤ ├─────────────┬─────────────┤
    │             │             │ │             │             │
    └─────────────┴─────────────┘ └─────────────┴─────────────┘
    ```
  - You can define the rules or layouts for each windows just in plain text in the config:
    ```
    [1]
    [1 1]  /1 1/
    [1 2]  [1 1 1]  /2 1/
    [2 2]  [1 2 1]  [1 1 2]  [1 3]  [1 1 1 1]
    [2 1 2]  [1 2 2]  /2 3/  [1 1 1 1 1]
    ```
  - One more thing you can define is the ratios at which want your windows to be split at:
    ```
                 1:1                                2:1
    ┌─────────────┬─────────────┐ ┌──────────────────┬────────┐
    │             │             │ │                  │        │
    │             │             │ │                  │        │
    │             │             │ │                  │        │
    └─────────────┴─────────────┘ └──────────────────┴────────┘
    ```
    And also define them within the config:
    ```
    2:1  3:2  1:1  2:3  1:2
    1:1:1  2:1:1  1:2:1  1:1:2
    1:1:1:1  2:1:1:1  1:2:1:1  1:1:2:1  1:1:1:2
    ```
  - You can cycle between the layouts, cycle the ratio for vertical or horizontal split using a shortcut key or the toggle menu.
  - You can also apply transform to modify current layout:
    | Transformation | no mirror | mirror |
    | :------------- | :-------- | :----- |
    | **no rotate**  | [1 2]<br><pre>┌───┬───┐<br>│   │   │<br>│   ├───┤<br>│   │   │<br>└───┴───┘</pre> | [2 1]<br><pre>┌───────┐<br>│       │<br>├───┬───┤<br>│   │   │<br>└───┴───┘</pre> |
    | **rotate**     | /1 2/<br><pre>┌───┬───┐<br>│   │   │<br>├───┤   │<br>│   │   │<br>└───┴───┘</pre> | /2 1/<br><pre>┌───┬───┐<br>│   │   │<br>├───┴───┤<br>│       │<br>└───────┘</pre> |
  - Other than that you can:
    - cycle the order of windows
    - toggle monocle layout
    - toggle floating for active window
    - toggle tiling entirely
    - Define different sets of config like above.
  - It uses a saver script that saves all the tiling state of each screen and desktop and remembers it. so the state persists even after logout/shutdown.
- It features an overview desktop effect which integrate well with the script:
  - You can toggle with a shortcut key.
  - enable cursor transpose feature to move your cursor to exactly the place where you clicked on or while you toggle the overview.
  - select with the left click
  - close with middle click
  - additional option with right click
  - drag the windows to another desktop or an empty one with left click drag.
  - clone a window into another desktop with right click drag.
  - features multiple media player controller on top right corner.
    - on left click on the media art. takes you to the desktop and window where the media is playing.
    - it has seekbar, cycleable speed, play/pause, next/previous
