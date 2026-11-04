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
  - \[1 2\] respresents a row of windows where each number represent how many in their stack
    ```
    ┌──────────────┬──────────────┐
    │              │              │
    │              ├──────────────┤
    │              │              │
    └──────────────┴──────────────┘
    ```
  - \\1 2\\ represents the same but rotated -90 degrees
    ```
    ┌─────────────────────────────┐
    │                             │
    ├──────────────┬──────────────┤
    │              │              │
    └──────────────┴──────────────┘
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
    1:1                             2:1
    ┌──────────────┬──────────────┐ ┌────────────────────┬────────┐
    │              │              │ │                    │        │
    │              │              │ │                    │        │
    │              │              │ │                    │        │
    └──────────────┴──────────────┘ └────────────────────┴────────┘
    ```
    And also define them within the config:
    ```
    2:1  3:2  1:1  2:3  1:2
    1:1:1  2:1:1  1:2:1  1:1:2
    1:1:1:1  2:1:1:1  1:2:1:1  1:1:2:1  1:1:1:2
    ```
    
