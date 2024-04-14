# Fantasy Baseball Draft

> **Note:** This repo is related to my final project for ISE501 at NC State University.

## Overview

This project is intended to develop a mixed-integer linear programming (MIP) model to determine the best fantasy baseball team to draft for the 2024 season subject to my league's unique rules. Scoring for my league is standard 5x5 roto with two exceptions:

- HR
- R
- RBI
- SB
- **OBP**
- W
- **SOLD**
- SO
- WHIP
- ERA

Targets were set based on the league leaders at the end of the 2023 season. The goal of the model is to draft a well-balanced roster that meets all targets and satisfies draft position and positional eligibility requirements.

Data for the model is sourced from [Fangraphs](https://www.fangraphs.com) for preseason player projections from several systems:

- ZiPS
- Steamer
- ATC
- THE BAT
- THE BAT X

Draft position and related data was obtained from the [**N**ational **F**antasy **B**aseball **C**hampionship \(NFBC)](https://nfc.shgn.com/high-stakes-fantasy-baseball). Specifically, Rotowire Online 12-team leagues with drafts during the month of March was used to approximate the behavior of other teams in my league.

Multiple scenario analyses will be performed to determine the effect of various inputs used on the results of the model including:

- Projection system
- Starting draft position
- Proxy for player draft value