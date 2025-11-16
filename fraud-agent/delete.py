import sys
import vertexai
from vertexai import agent_engines
from typing import List


def main():
  """Deletes a deployed Vertex AI Agent Engine agent with a specific short ID,
  forcing deletion of child resources.

  Usage: python delete_agent.py <PROJECT_ID> <LOCATION> <AGENT_SHORT_ID>
  The AGENT_SHORT_ID is the numeric ID (e.g., 98765), not the full resource path.
  """

  # Checks for exactly 4 command-line arguments (script name + 3 arguments)
  if len(sys.argv) != 4:
    print("Usage: python delete_agent.py <PROJECT_ID> <LOCATION> <AGENT_SHORT_ID>", file=sys.stderr)
    sys.exit(1)

  # Assigns arguments
  project_id = sys.argv[1]
  location = sys.argv[2]
  short_agent_id = sys.argv[3]

  print(f"--- Attempting to Delete Fraud Agent ---")
  print(f"Project ID: {project_id}")
  print(f"Location: {location}")
  print(f"Searching for short Agent ID: {short_agent_id}")

  try:
    # Initialize the Vertex AI SDK using the arguments
    vertexai.init(
        project=project_id,
        location=location
    )

    # 1. List agents and search for the specific short ID provided
    print("Searching for agent by short ID...")

    # --- DEBUGGABLE FOR LOOP REPLACEMENT ---
    target_agent = None
    for app in agent_engines.list():
      print(f"DEBUG: Checking agent: {app.name}")  # Example print statement for debugging

      # Check if the last segment of the resource name matches the provided short ID
      # NOTE: This logic seems to assume app.name holds the short ID, which is common
      # for ADK apps if they follow the 'agents/<ID>' format and app.name is just the ID.
      # Resource names are typically 'projects/.../locations/.../agents/<ID>'.
      if app.name.endswith(f"/{short_agent_id}") or app.name == short_agent_id:
        target_agent = app
        break  # Stop searching once found
    # --- END OF DEBUGGABLE FOR LOOP ---

    if not target_agent:
      print(f"⚠️ Agent with short ID '{short_agent_id}' not found. Nothing to delete.")
      return

    # 2. Delete the found agent instance
    print(f"✅ Found agent: {target_agent.name}. Deleting resource...")
    # Call the delete method directly on the object, which you confirmed works.
    target_agent.delete(
        force=True
    )

    print(f"✅ Agent '{target_agent.name}' and all associated resources deleted successfully.")

  except Exception as e:
    error_message = str(e)
    if "Permission denied" in error_message:
      print(f"❌ PERMISSION DENIED: Please ensure the user running this script has the 'roles/aiplatform.admin' role on project '{project_id}'.")
      print(f"Original Error: {error_message}", file=sys.stderr)
      sys.exit(1)

    print(f"❌ An error occurred during agent deletion: {e}", file=sys.stderr)
    sys.exit(1)

if __name__ == "__main__":
  main()