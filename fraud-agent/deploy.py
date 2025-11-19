"""
Initializes and deploys the Fraud Agent application using the Vertex AI
Agent Engine SDK.

The agent uses implicit session management and loads deployment dependencies
from pyproject.toml.

Usage: python deploy.py <PROJECT_ID> <REGION>
"""
import os
import sys
import tomllib
from typing import Any, Dict, Optional, List

import vertexai
from vertexai import agent_engines
from google.adk.sessions.vertex_ai_session_service import (
  VertexAiSessionService,
)

# Local/Project Imports
from implicit_session_service import ImplicitSessionService
# IMPORTS AGENT CREATION FUNCTION: Reads the function from agent/agent.py
from agent.agent import create_root_agent


# --- Global State ---
_session_service: Optional[ImplicitSessionService] = None
# This dictionary holds the configuration (Project ID, Region, etc.) parsed from CLI
_CONFIG: Dict[str, Any] = {}

# --- Pub/Sub Constants for Agent Configuration ---
# These are the IDs of the topics that the agent will publish to.
AUGMENTED_TOPIC_ID = "fraud-example-augmented-transactions"
COMPROMISED_TOPIC_ID = "fraud-example-compromised-cards"


def get_session_service() -> ImplicitSessionService:
  """
  Initializes the ImplicitSessionService lazily as a singleton, reading
  configuration from the global _CONFIG dictionary.

  This function acts as the session_service_builder for the AdkApp.
  """
  global _session_service
  if _session_service is None:
    # Read configuration from the global dictionary populated in main()
    project_id = _CONFIG["PROJECT_ID"]
    location = _CONFIG["REGION"]

    # 1. Initialize the core Vertex AI Session Service
    vertex_session_service = VertexAiSessionService(
        project=project_id,
        location=location,
    )
    # 2. Wrap it in the required ImplicitSessionService
    _session_service = ImplicitSessionService(vertex_session_service)
  return _session_service


def load_requirements() -> List[str]:
  """
  Loads Python dependency requirements from the 'project.dependencies'
  section of pyproject.toml.
  """
  # Uses os.path.dirname(__file__) for robust path resolution relative to the script
  pyproject_path = os.path.abspath(
      os.path.join(os.path.dirname(__file__), "pyproject.toml")
  )

  # Using 'with' statement ensures the file is properly closed
  with open(pyproject_path, "rb") as f:
    pyproject_data = tomllib.load(f)

  # Note: Using List[str] in function signature for better type hint consistency
  return pyproject_data["project"]["dependencies"]


def main():
  """Handles command-line arguments and application deployment."""
  global _CONFIG

  # Check for correct number of arguments (script name + 2 arguments)
  if len(sys.argv) != 3:
    print("Usage: python deploy.py <PROJECT_ID> <REGION>", file=sys.stderr)
    sys.exit(1)

  # Parse arguments
  project_id = sys.argv[1]
  location = sys.argv[2]
  staging_bucket = "gs://fraud-example-staging-" + project_id

  # Store configuration globally for access by get_session_service
  _CONFIG["PROJECT_ID"] = project_id
  _CONFIG["REGION"] = location
  _CONFIG["STAGING_BUCKET"] = staging_bucket

  print(f"--- Deploying Fraud Agent ---")
  print(f"Project ID: {project_id}")
  print(f"Region: {location}")
  print(f"Staging Bucket: {staging_bucket}")

  # Initialize the Vertex AI SDK
  vertexai.init(
      project=project_id,
      location=location,
      staging_bucket=staging_bucket,
  )

  # 1. Instantiate the agent using the creation function and dynamic config
  # This calls agent/agent.py:create_root_agent with the CLI-provided project_id
  root_agent = create_root_agent(
      project_id=project_id,
      augmented_topic_id=AUGMENTED_TOPIC_ID,
      compromised_topic_id=COMPROMISED_TOPIC_ID
  )

  print("Starting AdkApp initialization...")

  # 2. Wrap the root agent in an AdkApp object
  app = agent_engines.AdkApp(
      agent=root_agent,
      enable_tracing=True,
      session_service_builder=get_session_service  # Uses global _CONFIG
  )

  # 3. Deploy or update the remote agent instance
  remote_app = agent_engines.create(
      app,
      display_name="Fraud Agent",
      requirements=load_requirements(),
      extra_packages=[
          "implicit_session_service.py",  # Explicitly includes the required session helper
          "./agent",  # Includes the agent/ directory
      ],
  )
  print(f"Remote agent created/updated successfully: {remote_app.display_name}")


if __name__ == "__main__":
  main()