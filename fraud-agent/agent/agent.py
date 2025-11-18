import sys
import logging
from typing import Dict, Any, List

from google.adk.agents import LlmAgent
from google.adk.tools import FunctionTool
from google.cloud import pubsub_v1
from google.cloud.pubsub_v1.types import BatchSettings

# Configure basic logging (recommended over print statements for better visibility in deployments)
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

# --- Define Constants & Globals ---
MODEL_NAME: str = "gemini-2.5-flash"

# Cache for Pub/Sub publisher clients, one per topic.
_publishers: Dict[str, pubsub_v1.PublisherClient] = {}


# --- Define Tool(s) ---

def publish_record(topic: str, json_payload: str) -> Dict[str, Any]:
  """
  Publishes a JSON string payload to a Google Cloud Pub/Sub topic.

  This tool is synchronous and waits for the publish operation to complete.

  Args:
      topic: The full topic path (e.g., 'projects/id/topics/name').
      json_payload: The JSON string data to publish.

  Returns:
      A dictionary (empty on success). The dictionary return type is
      required by the Agent Engine tool contract.
  """
  logging.info(f"Attempting to publish to topic: {topic}")

  # Use a dictionary lookup/creation pattern for the PublisherClient
  publisher = _publishers.get(topic)
  if publisher is None:
    # Define the batch settings:
    # max_messages=1 ensures that as soon as the publisher.publish() is called,
    # the single message is sent immediately without waiting for other messages.
    custom_batch_settings = BatchSettings(max_messages=1)

    # Instantiate the PublisherClient with the custom batch settings
    publisher = pubsub_v1.PublisherClient(batch_settings=custom_batch_settings)
    _publishers[topic] = publisher

  try:
    # The publisher client requires data to be a bytestring.
    data = json_payload.encode("utf-8")

    # Publish the message and wait for the future to complete.
    future = publisher.publish(topic, data)
    future.result()

    logging.info("Successfully published!")

  except Exception as e:
    # Use stderr for critical failure messages
    logging.error(f"Could not publish record to {topic}: {e}")
    # Return an empty dictionary on failure, matching the contract
    return {}

  # Return an empty dictionary on success as required by the Agent Engine tool contract.
  return {}


# --- Initialize Agent Creation Function ---

def create_root_agent(
    project_id: str,
    augmented_topic_id: str,
    compromised_topic_id: str
) -> LlmAgent:
  """
  Creates and configures the FraudDetector LLM agent with dynamic topic paths.

  Args:
      project_id: The GCP project ID where the topics reside.
      augmented_topic_id: The ID of the topic for augmented transactions.
      compromised_topic_id: The ID of the topic for compromised card alerts.

  Returns:
      An LlmAgent instance configured with dynamic global instructions.
  """

  # 1. Construct the full Pub/Sub topic paths
  augmented_topic_path = f"projects/{project_id}/topics/{augmented_topic_id}"
  compromised_topic_path = f"projects/{project_id}/topics/{compromised_topic_id}"

  # 2. Define the global instruction using f-string formatting
  # Note: Double braces {{ and }} are used to output literal braces in the JSON samples.
  global_instruction_template = f"""
        You are an expert agent at detecting fraud in financial transactions. You will be given JSON records
        for credit card transactions where you are trying to determine the likelihood of fraud. Possible indicators of fraud:
        - A sequence of transactions for the same credit card using IP addresses from different countries.
        - A sequence of transactions where the first is a small amount of money to a charity and then a large amount of money to a store.
        - Anything else you can find as an expert in fraud detection using resources available to you on the web.

        For each transaction:
        1. Evaluate the likelihood of it being a fraudulent transaction and give it a score between 0.0 and 1.0.
        2. Augment the input with two new fields: 'fraud_likelihood' set to this result of this evaluation and 'fraud_reason' with a short description of the reason for the fraud likelihood.
        3. Use "publish_record" to publish this augmented JSON object to the topic {augmented_topic_path}
        4. If the evaluation of fraud from step 1 is > 0.7, use "publish_record" to publish a JSON object containing the timestamp, credit card number, fraud likelihood, and fraud reason to the topic {compromised_topic_path}.
        5. Return the augmented input from step #3.

        Sample input: {{"credit_card_number": "1234567812345678", "receiver": "Macy's", "amount": 100.05, "ip_address": "68.45.25.58", "timestamp":"2025-09-18T11:47:02.814"}}
        Sample output: {{"credit_card_number": "1234567812345678", "receiver": "Macy's", "amount": 100.05, "ip_address": "68.45.25.58", "timestamp":"2025-09-18T11:47:02.814", "fraud_likelihood": 0.8, "fraud_reason": "Multiple transactions from different countries"}}
        """

  # 3. Instantiate and return the agent
  return LlmAgent(
      model=MODEL_NAME,
      name="FraudDetector",
      description="Determines risk of fraud in transactions.",
      global_instruction=global_instruction_template,
      tools=[FunctionTool(publish_record)],
  )
