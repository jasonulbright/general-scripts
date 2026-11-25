# Maintenance

Baselines and packages that clean up data on clients on a schedule. Each folder is one tool. Open its README for the details.

## Contents

| Folder | Purpose |
|--------|---------|
| [`User-Profile-Cleanup/`](User-Profile-Cleanup/) | Removes stale and orphaned user profile data. Three ways to run it: a CI and baseline, a package on a recurring schedule, or a task sequence step. Each creator asks for the day count (30, 60, 90 and so on) and puts it in the object names. |
