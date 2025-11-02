"""Utilities for determining environment setup versions."""

import json
import subprocess

from bcbench.config import get_config
from bcbench.logger import get_logger

logger = get_logger(__name__)


def determine_environment_setup_version(commit: str) -> str:
    """Determine the appropriate environment setup version based on commit availability in release branches."""
    config = get_config()

    result = subprocess.run(
        ["git", "show", "master:Directory.App.Props.json"],
        cwd=config.paths.nav_repo_path,
        capture_output=True,
        text=True,
        check=True,
    )
    props_data = json.loads(result.stdout)
    current_version_str = props_data["variables"]["app_currentVersion"]
    current_major_version = int(current_version_str.split(".")[0])

    start_version = current_major_version - 1

    for major_version in range(start_version, 20, -1):
        for minor_version in [5, 4, 3, 2, 1, 0]:
            branch_name = f"releases/{major_version}.{minor_version}"

            branch_check = subprocess.run(
                [
                    "git",
                    "show-ref",
                    "--verify",
                    "--quiet",
                    f"refs/remotes/origin/{branch_name}",
                ],
                cwd=config.paths.nav_repo_path,
                capture_output=True,
            )

            if branch_check.returncode == 0:
                commit_check = subprocess.run(
                    [
                        "git",
                        "merge-base",
                        "--is-ancestor",
                        commit,
                        f"origin/{branch_name}",
                    ],
                    cwd=config.paths.nav_repo_path,
                    capture_output=True,
                )

                if commit_check.returncode != 0:
                    return f"{major_version}.{minor_version}"

    return ""
