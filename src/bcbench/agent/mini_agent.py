"""mini-bc-agent implementation using mini-swe-agent."""

import json
import os
import re
from pathlib import Path
from typing import Optional, TYPE_CHECKING

import typer
import yaml
from dotenv import load_dotenv

from bcbench.core.dataset_entry import DatasetEntry
from bcbench.core.utils import DATASET_PATH, colored, GREY
from bcbench.core.logger import get_logger

load_dotenv()

# Lazy imports to avoid mini-swe-agent startup message for non-agent commands
if TYPE_CHECKING:
    from minisweagent.agents.default import DefaultAgent, FormatError  # noqa: F401
    from minisweagent.models.litellm_model import LitellmModel  # noqa: F401
    from bcbench.agent.bc_environment import BCEnvironment  # noqa: F401

logger = get_logger(__name__)


def load_entry_from_dataset(instance_id: str) -> DatasetEntry:
    """Load a dataset entry by instance ID."""
    with open(DATASET_PATH, "r", encoding="utf-8") as f:
        for line in f:
            data = json.loads(line.strip())
            if data.get("instance_id") == instance_id:
                return DatasetEntry.from_json(data)

    raise ValueError(f"Entry with instance_id '{instance_id}' not found in dataset")


def build_task_description(entry: DatasetEntry) -> str:
    """Build a task description from a dataset entry."""
    task = entry.problem_statement
    if entry.hints_text:
        task += f"\n\n## Additional Hints\n{entry.hints_text}"
    logger.info(f"Task description:\n{colored(task, GREY)}")
    return task


def _create_bc_agent_class():
    """Lazy creation of BCAgent class to avoid importing mini-swe-agent at module load."""
    from minisweagent.agents.default import DefaultAgent, FormatError

    class BCAgent(DefaultAgent):
        """BC-specific agent extending DefaultAgent."""

        def query(self) -> dict:
            """Query the model with current messages."""
            logger.debug(f"============================ Current step: {self.model.n_calls} =============================")
            return super().query()

        def parse_action(self, response: dict) -> dict:
            """Parse the action from the message. Returns the action."""
            logger.debug(f"Agent response content:\n{colored(response['content'], GREY)}")
            actions = re.findall(r"```powershell\s*\n(.*?)\n```", response["content"], re.DOTALL)
            if len(actions) == 1:
                return {"action": actions[0].strip(), **response}
            raise FormatError(self.render_template(self.config.format_error_template, actions=actions))

    return BCAgent


def run_agent(
    instance_id: str,
    repo_path: Path,
    use_container: bool = False,
    container_name: Optional[str] = None,
    username: str = "admin",
    password: Optional[str] = None,
    step_limit: int = 20,
    cost_limit: float = 1.0,
) -> None:
    """
    Run the mini BC agent on a dataset entry.

    Args:
        instance_id: Instance ID from the dataset
        repo_path: Path to NAV repository (defaults to NAV_REPO_PATH)
        use_container: Whether to use containerized BC environment
        container_name: BC container name (required if use_container is True)
        username: Username for BC container
        password: Password for BC container (or set BC_CONTAINER_PASSWORD env var)
        step_limit: Maximum number of agent steps
        cost_limit: Maximum cost limit for agent

    Raises:
        typer.Exit: Exits with code 1 on failure
    """
    # Validate container parameters
    if use_container:
        if container_name is None:
            logger.error("--container-name is required when --use-container is enabled")
            raise typer.Exit(code=1)

        if password is None:
            password = os.environ.get("BC_CONTAINER_PASSWORD")
            if password is None:
                logger.error("Password required when --use-container is enabled. Set --password or BC_CONTAINER_PASSWORD env var")
                raise typer.Exit(code=1)

    try:
        entry: DatasetEntry = load_entry_from_dataset(instance_id)
    except ValueError as exc:
        logger.error(str(exc))
        raise typer.Exit(code=1)
    except Exception as exc:
        logger.error(f"Failed to load dataset entry: {exc}")
        raise typer.Exit(code=1)

    config_file: Path = Path(__file__).parent / "bc_agent_config.yaml"
    _config = yaml.safe_load(config_file.read_text())
    agent_config = _config.get("agent", {})
    agent_config["step_limit"] = step_limit
    agent_config["cost_limit"] = cost_limit

    task: str = build_task_description(entry)

    try:
        # Lazy import to avoid mini-swe-agent startup message
        from minisweagent.models.litellm_model import LitellmModel
        from bcbench.agent.bc_environment import BCEnvironment

        BCAgent = _create_bc_agent_class()

        agent = BCAgent(
            LitellmModel(model_name="azure/gpt-4.1"),
            BCEnvironment(
                container_name=container_name or "",
                nav_repo_path=str(repo_path),
                username=username,
                password=password or "",
                project_paths=entry.project_paths,
                cwd=str(repo_path),
                enable_bc_tools=use_container,
            ),
            **agent_config,
        )

        agent.run(task)
        logger.info("Agent completed successfully")

    except Exception as exc:
        logger.error(f"Agent execution failed: {exc}")
        raise typer.Exit(code=1)
