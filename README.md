# BC Bench

Inspired by [SWE-Bench](https://github.com/swe-bench/SWE-bench), for Business Central (AL) ecosystem.

Codebase is bit messy for now, will clean up once we are further in the progress.

## Repo at a glance

| Path | Purpose |
| --- | --- |
| `dataset/` | dataset schema and some minimal entries for now |
| `scripts/python/` | Python utilities for collecting and validating dataset |
| `scripts/powershell/` | PowerShell modules for environment setup using AL-GO/BCContainerHelper |
| `vscode-extension/` | Expanding on POC from Thaddeus, a small VS Code extension that helps automation within VSCode |

## Quick start

There are a few entry points where you can start to play around.

Many of the scripts assumes below folder structure:
```
C:\depot\BC-Bench
C:\depot\NAV
```

### Collection Data from NAV

Pre-requisite, generate a PAT from ADO for with READ access to 1. Code 2. Work Items

Put the generated PAT into .env file under the root like below
```
# .env
ADO_TOKEN=
```

Running the script:

```
cd scripts/python
pip install -r requirements.txt
python collection_nav.py 210528
```

### Workflow for Dataset Validation

Go to the `Actions` tab on GitHub or `.github\workflows` folder, you will find a `Dataset validation` workflow. It currently has two steps:
1. Run `scripts\python\validate_dataset_schema.py` to statically validate the dataset scheme
2. Setting up environment for each unique version (e.g. 26.5) with `scripts\powershell\Setup-ValidationEnvironment.ps1`
3. TODO: Checkout `base_commit`
4. TODO: Apply Test Patch
5. TODO: Test should fail

### Environment Setup

Do NOT run `Setup-ValidationEnvironment.ps1` locally. Try `Evaluate.ps1` instead. It is still incomplete tho.

### VSCode Extension

1. `cd vscode-extension && npm install`
2. Install the Extension
3. Run Command "BC Bench: Start Automation"

## Dataset notes

Follows the [SWE-Bench schema](https://huggingface.co/datasets/SWE-bench/SWE-bench_Verified) with adjustments:

- Modified `environment_setup_commit` to `environment_setup_version`. We need a version to setup environment via `Get-BCArtifactUrl -version`.
- Added `project_paths` enumerates AL project roots touched by the fix.
- TODO: we might not need the Version field
- TODO: How to list tests? Need to figure out how to run them first I guess

See the authoritative spec in [`dataset/schema.json`](./dataset/schema.json).

## Next

### Mini-BCBench-Agent for Baseline

Reading [mini-swe-agent](https://github.com/SWE-agent/mini-SWE-agent), realized that they faced similar problems.

> Currently, top-performing systems represent a wide variety of AI scaffolds; from simple LM agent loops, to RAG systems, to multi-rollout and review type systems. Each of these systems are totally valid solutions to the problem of solving GitHub issues.

Steffen brought up a good point asking "what does VSCode gives us". Reflecting now, it essentially gives us a free agent loop, no need to do any scaffolding ourselves.

It would be beneficial to have a `Mini-BCBench-Agent` with a minimal agent to establish a baseline, and we know for sure this can run in our pipeline.

### Automated Evaluation in DevBox

Digging a bit deeper into the automation part, I'm not so sure that we could run a full evaluation with VSCode (at least ChatGPT tells me it's not designed for it...).

Spinning up a automation within DevBox should be much straightforward.

### ALC.exe

Not critical, but can we get `alc.exe` directly somehow? Remember it's mentioned that we extract that out from the AL Language Extension nowadays in AL-Go/BCContainerHelper.

We still need to spin up BCContainerHelper to run tests, but it should give us better performance if it's separated.

### Dataset Collection

Not sure to say here, just work.